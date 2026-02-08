module kernelWindow #(
    parameter MAX_LB_WIDTH = 8192
)
(
    input  logic        clk,
    input  logic        rst,
    
    input  logic [31:0] img_width,
    input  logic [31:0] in_channels,
    
    input  logic [7:0]  pixel_in,
    input  logic        data_valid,
    output logic [7:0]  window [0:2][0:2],
    output logic        valid_out
);

    logic [31:0] total_row_width;
    assign total_row_width = img_width * in_channels;

    logic [7:0] out1;
    logic [7:0] out2;

    logic [7:0] row1_aligned;
    logic [7:0] row2_delayed_1, row2_aligned;

    always_ff @(posedge clk) begin
        if (rst) begin
            row1_aligned   <= '0;
            row2_delayed_1 <= '0;
            row2_aligned   <= '0;
        end else if (data_valid) begin
            row1_aligned   <= out1;           
            row2_delayed_1 <= pixel_in;       
            row2_aligned   <= row2_delayed_1; 
        end
    end

    lineBuffer #(.MAX_WIDTH(MAX_LB_WIDTH)) LineBuffer1 (
        .clk(clk),
        .rst(rst),
        .curr_width(total_row_width),
        .pixel(pixel_in),
        .data_valid(data_valid),
        .o_data(out1)
    );

    lineBuffer #(.MAX_WIDTH(MAX_LB_WIDTH)) LineBuffer0 (
        .clk(clk),
        .rst(rst),
        .curr_width(total_row_width),
        .pixel(out1),
        .data_valid(data_valid),
        .o_data(out2)
    );

    logic [31:0] delay_count; 
    logic        priming_done;

    always_ff @(posedge clk) begin
        if (rst) begin
            delay_count  <= '0;
            priming_done <= '0;
            valid_out    <= '0;
            for (int i=0; i<3; i++) begin
                for (int j=0; j<3; j++) window[i][j] <= '0;
            end
        end else if (data_valid) begin

            window[2][0] <= out2;
            window[2][1] <= window[2][0];
            window[2][2] <= window[2][1];

            window[1][0] <= row1_aligned;
            window[1][1] <= window[1][0];
            window[1][2] <= window[1][1];

            window[0][0] <= row2_aligned;
            window[0][1] <= window[0][0];
            window[0][2] <= window[0][1];

            if (!priming_done) begin
                if (delay_count == (2*total_row_width + 2))
                    priming_done <= 1'b1;
                else
                    delay_count <= delay_count + 1'b1;
            end
            
            valid_out <= priming_done;
        end else begin
            valid_out <= 1'b0;
        end
    end

endmodule
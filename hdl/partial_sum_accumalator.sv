module partial_sum_accumulator #(
    parameter MAX_WIDTH = 512
)(
    input  logic        clk,
    input  logic        rst,
    
    input  logic [31:0] conv_data_in,
    input  logic        conv_valid_in,
    
    input  logic        is_first_channel,
    input  logic        is_last_channel,
    input  logic [$clog2(MAX_WIDTH)-1:0] pixel_idx,
    
    output logic [31:0] accum_data_out,
    output logic        accum_valid_out
);

    (* ram_style = "block" *)
    logic [31:0] partial_sum_mem [MAX_WIDTH-1:0];

    logic [31:0] conv_data_q;
    logic        is_first_q, is_last_q, valid_q;
    logic [$clog2(MAX_WIDTH)-1:0] pixel_idx_q;
    
    logic [31:0] old_sum;

    always_ff @(posedge clk) begin
        if (rst) begin
            conv_data_q     <= '0;
            is_first_q      <= '0;
            is_last_q       <= '0;
            valid_q         <= '0;
            pixel_idx_q     <= '0;
            old_sum         <= '0;
            accum_data_out  <= '0;
            accum_valid_out <= '0;
        end else begin
            old_sum <= partial_sum_mem[pixel_idx];
            conv_data_q <= conv_data_in;
            is_first_q  <= is_first_channel;
            is_last_q   <= is_last_channel;
            pixel_idx_q <= pixel_idx;
            valid_q     <= conv_valid_in;

            if (valid_q) begin
                logic [31:0] new_sum;
                new_sum = is_first_q ? conv_data_q : (old_sum + conv_data_q);
                
                partial_sum_mem[pixel_idx_q] <= new_sum;
                
                if (is_last_q) begin
                    accum_data_out  <= new_sum;
                    accum_valid_out <= 1'b1;
                end else begin
                    accum_valid_out <= 1'b0;
                end
            end else begin
                accum_valid_out <= 1'b0;
            end
        end
    end

endmodule
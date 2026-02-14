module weight_manager #(
    parameter DEPTH = 4096,
    parameter ADDR_WIDTH = $clog2(DEPTH)
)(
    input logic clk,
    input logic rst,

    input logic write_mode,
    input logic data_valid,
    input logic [71:0] data_in,
    output logic write_complete,

    input logic [9:0] cfg_ci_groups,
    input logic [9:0] cfg_co_groups,

    input logic read_en,
    output logic data_ready,
    output logic [575:0] data_out [0:7],
    output logic read_complete
);

logic [12:0] write_ch_cnt;
logic [12:0] write_f_cnt;
logic [ADDR_WIDTH-1:0] waddr;

assign waddr = (write_f_cnt >> 3) * cfg_ci_groups + (write_ch_cnt >> 3);

logic [2:0] bank_sel;
assign bank_sel = write_f_cnt[2:0];

logic [2:0] uram_sel;
assign uram_sel = write_ch_cnt[2:0];

logic [7:0] bank_wen_vec [0:7];

always_ff @(posedge clk) begin
    if (rst) begin
        write_ch_cnt   <= 0;
        write_f_cnt    <= 0;
        write_complete <= 0;
    end else if (write_mode) begin
        if (data_valid) begin
            if (write_ch_cnt >= (cfg_ci_groups << 3) - 1) begin
                write_ch_cnt <= 0;
                if (write_f_cnt >= (cfg_co_groups << 3) - 1) begin
                    write_f_cnt    <= 0;
                    write_complete <= 1;
                    $display("[%0t] WM DEBUG: Write sequence complete. Filters: %0d, Channels: %0d", $time, write_f_cnt + 1, write_ch_cnt + 1);
                end else begin
                    write_f_cnt <= write_f_cnt + 1;
                end
            end else begin
                write_ch_cnt <= write_ch_cnt + 1;
            end
        end
    end else begin
        write_ch_cnt   <= 0;
        write_f_cnt    <= 0;
        write_complete <= 0;
    end
end

always_comb begin
    for(int i=0;i<8;i++) begin
        if(write_mode && data_valid && bank_sel == i) begin
            bank_wen_vec[i] = (1 << uram_sel);
        end else begin
            bank_wen_vec[i] = 8'b0;
        end
    end
end

// read mechanism

logic [ADDR_WIDTH-1:0] read_address;
logic [9:0] input_ch_gr_counter;
logic [9:0] output_ch_gr_counter;
logic [2:0] ready_pipe;
logic [2:0] complete_pipe;
logic read_done_raw;

assign read_address  = input_ch_gr_counter + (output_ch_gr_counter * cfg_ci_groups);
assign data_ready    = ready_pipe[2];
assign read_complete = complete_pipe[2];

always_ff @(posedge clk) begin
    if (rst) begin
        input_ch_gr_counter  <= 0;
        output_ch_gr_counter <= 0;
        read_done_raw        <= 0;
        ready_pipe           <= 3'b0;
        complete_pipe        <= 3'b0;
    end else begin
        ready_pipe    <= {ready_pipe[1:0], read_en};
        complete_pipe <= {complete_pipe[1:0], read_done_raw};

        if (read_en) begin
            read_done_raw <= 0;
            if (input_ch_gr_counter >= cfg_ci_groups - 1) begin
                input_ch_gr_counter <= 0;
                if (output_ch_gr_counter >= cfg_co_groups - 1) begin
                    output_ch_gr_counter <= 0;
                    read_done_raw        <= 1;
                end else begin
                    output_ch_gr_counter <= output_ch_gr_counter + 1;
                end
            end else begin
                input_ch_gr_counter <= input_ch_gr_counter + 1;
            end
        end
    end
end

genvar i, j;
generate
    for (i = 0; i < 8; i++) begin : bank_gen
        logic wen_unpacked [0:7];
        logic ren_unpacked [0:7];

        for (j = 0; j < 8; j++) begin : ctrl_map
            assign wen_unpacked[j] = bank_wen_vec[i][j];
            assign ren_unpacked[j] = read_en;
        end

        weight_bank #(
            .DEPTH (DEPTH)
        ) u_bank (
            .clk   (clk),
            .rst   (rst),
            .wen   (wen_unpacked),
            .wdata (data_in),
            .waddr (waddr),
            .ren   (ren_unpacked),
            .raddr (read_address),
            .rdata (data_out[i])
        );
    end
endgenerate


endmodule
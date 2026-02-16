module weight_manager #(
    parameter DEPTH = 4096,
    parameter ADDR_WIDTH = $clog2(DEPTH)
)(
    input logic clk,
    input logic rst,

    // write port — CPU streams 72-bit words, auto-routing
    input logic        wr_en,
    input logic [71:0] wr_data,

    // read port — conv controller supplies address
    input logic                    rd_en,
    input logic [ADDR_WIDTH-1:0]   rd_addr,
    output logic [575:0]           data_out [0:7],
    output logic                   data_ready
);

// ── Write: auto-incrementing counter, bit-slice routing ──

logic [ADDR_WIDTH+5:0] wr_cnt;

wire [2:0]              uram_sel = wr_cnt[2:0];
wire [2:0]              bank_sel = wr_cnt[5:3];
wire [ADDR_WIDTH-1:0]   waddr   = wr_cnt[ADDR_WIDTH+5:6];

logic [7:0] bank_wen_vec [0:7];

always_ff @(posedge clk) begin
    if (rst)
        wr_cnt <= 0;
    else if (wr_en)
        wr_cnt <= wr_cnt + 1;
end

always_comb begin
    for (int i = 0; i < 8; i++) begin
        if (wr_en && bank_sel == i)
            bank_wen_vec[i] = 8'(1 << uram_sel);
        else
            bank_wen_vec[i] = 8'b0;
    end
end

// ── Read: 3-cycle latency pipeline (matches conv_pe pipeline) ──

logic [2:0] ready_pipe;

assign data_ready = ready_pipe[2];

always_ff @(posedge clk) begin
    if (rst)
        ready_pipe <= 3'b0;
    else
        ready_pipe <= {ready_pipe[1:0], rd_en};
end

// ── 8 weight banks ──

genvar i, j;
generate
    for (i = 0; i < 8; i++) begin : bank_gen
        logic wen_unpacked [0:7];
        logic ren_unpacked [0:7];

        for (j = 0; j < 8; j++) begin : ctrl_map
            assign wen_unpacked[j] = bank_wen_vec[i][j];
            assign ren_unpacked[j] = rd_en;
        end

        weight_bank #(
            .DEPTH (DEPTH)
        ) u_bank (
            .clk   (clk),
            .rst   (rst),
            .wen   (wen_unpacked),
            .wdata (wr_data),
            .waddr (waddr),
            .ren   (ren_unpacked),
            .raddr (rd_addr),
            .rdata (data_out[i])
        );
    end
endgenerate

endmodule

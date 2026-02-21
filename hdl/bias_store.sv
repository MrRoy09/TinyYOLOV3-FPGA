// Bias storage: 8 x 32-bit biases per output group
// Multi-OG: wr_addr_rst only on first OG so addresses accumulate
module bias_store #(
    parameter MAX_DEPTH  = 256,
    parameter ADDR_WIDTH = $clog2(MAX_DEPTH)
)(
    input  logic        clk,
    input  logic        rst,
    input  logic                  wr_en,
    input  logic [127:0]          wr_data,
    input  logic                  wr_addr_rst,
    input  logic                  rd_en,
    input  logic [ADDR_WIDTH-2:0] rd_group,
    output logic [31:0]           bias_out [0:7],
    output logic                  rd_valid
);

logic [127:0] bram [0:MAX_DEPTH-1];
logic [ADDR_WIDTH-1:0] wr_addr;

always_ff @(posedge clk) begin
    if (wr_addr_rst)
        wr_addr <= 0;
    else if (wr_en) begin
        bram[wr_addr] <= wr_data;
        wr_addr       <= wr_addr + 1;
    end
end

logic [127:0] rd_a, rd_b;
logic [ADDR_WIDTH-1:0] addr_a, addr_b;

assign addr_a = {rd_group, 1'b0};
assign addr_b = {rd_group, 1'b1};

always_ff @(posedge clk) begin
    if (rst) begin
        rd_valid <= 0;
        rd_a     <= '0;
        rd_b     <= '0;
    end else begin
        rd_valid <= rd_en;
        if (rd_en) begin
            rd_a <= bram[addr_a];
            rd_b <= bram[addr_b];
        end
    end
end

genvar i;
generate
    for (i = 0; i < 4; i++) begin : unpack_a
        assign bias_out[i] = rd_a[(i * 32) +: 32];
    end
    for (i = 0; i < 4; i++) begin : unpack_b
        assign bias_out[i + 4] = rd_b[(i * 32) +: 32];
    end
endgenerate

endmodule

module weight_bank #(
    parameter DEPTH = 4096,
    parameter ADDR_WIDTH = $clog2(DEPTH)
)
(   
    input logic clk,
    input logic rst,

    input logic wen [0:7],
    input logic [71:0] wdata,
    input logic [ADDR_WIDTH-1:0] waddr,

    input logic ren [0:7],
    input logic [ADDR_WIDTH-1:0] raddr,
    output logic [575:0] rdata
);


logic [71:0] bank_data[0:7];

genvar i, pos, ch;

generate
    for(i=0;i<8;i++) begin : uram_gen
        (* ram_style = "ultra" *)
        logic [71:0] memory [0:DEPTH-1];
        logic [71:0] rdata_pipe[0:2];

        always_ff @(posedge clk) begin
            if(wen[i]) begin
                memory[waddr] <= wdata;
            end
        end

        always_ff @(posedge clk) begin
            if (rst) begin
                rdata_pipe[0] <= '0;
                rdata_pipe[1] <= '0;
                rdata_pipe[2] <= '0;
            end else begin
                if (ren[i]) begin
                    rdata_pipe[0] <= memory[raddr];
                end
                rdata_pipe[1] <= rdata_pipe[0];
                rdata_pipe[2] <= rdata_pipe[1];
            end
        end

        assign bank_data[i] = rdata_pipe[2];

    end    
endgenerate

for (pos = 0; pos < 9; pos++) begin : pos_map
    for (ch = 0; ch < 8; ch++) begin : ch_map
        assign rdata[(pos*64 + ch*8) +: 8] = bank_data[ch][(pos*8) +: 8];
    end
end

endmodule
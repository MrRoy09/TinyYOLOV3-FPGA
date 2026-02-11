module weight_bank #(
    parameter DEPTH = 1024,
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

genvar i;

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
                if (ren[i])
                    rdata_pipe[0] <= memory[raddr];
                    rdata_pipe[1] <= rdata_pipe[0];
                    rdata_pipe[2] <= rdata_pipe[1];
            end
        end

        assign bank_data[i] = rdata_pipe[2];

    end    
endgenerate

assign rdata = {bank_data[7], bank_data[6], bank_data[5], bank_data[4],
                bank_data[3], bank_data[2], bank_data[1], bank_data[0]};

endmodule
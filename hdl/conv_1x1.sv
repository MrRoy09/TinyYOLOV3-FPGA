module conv_1x1 #()
(
    input logic clk,
    input logic rst,
    input logic valid_in,
    input logic last_channel,

    input logic [63:0] pixel,
    input logic [63:0] weights [0:7],
    input logic [31:0] biases [0:7],

    output logic [31:0] outs [0:7],
    output logic data_valid
);

logic [7:0] pe_valids;
assign data_valid = pe_valids[0];

genvar i;
generate
    for (i=0; i<8; i++) begin : pe_gen
        conv_1x1_pe PE (
            .clk(clk),
            .rst(rst),
            .valid_in(valid_in),
            .last_channel(last_channel),
            .pixel(pixel),
            .weights(weights[i]),
            .bias(biases[i]),
            .out(outs[i]),
            .data_valid(pe_valids[i])
        );
    end
endgenerate

endmodule

module conv_3x3 #()
(
    input logic clk,
    input logic rst,
    input logic valid_in,
    input logic last_channel,

    input logic [63:0] pixels [0:2][0:2],
    input logic [575:0] weights [0:7],
    input logic [31:0] biases [0:7],

    output logic [31:0] outs [0:7],
    output logic data_valid
);

logic [7:0] pe_data_valid;

genvar i;
generate
    for (i = 0; i < 8; i++) begin : pe_gen
        conv_pe ConvPE (
            .clk(clk),
            .rst(rst),
            .valid_in(valid_in),
            .last_channel(last_channel),
            .pixels(pixels),
            .weights(weights[i]),
            .bias(biases[i]),
            .out(outs[i]),
            .data_valid(pe_data_valid[i])
        );
    end
endgenerate

assign data_valid = pe_data_valid[0];

endmodule
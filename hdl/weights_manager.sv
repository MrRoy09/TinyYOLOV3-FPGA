module weight_manager #(
    parameter DEPTH = 1024,
    parameter ADDR_WIDTH = $clog2(DEPTH)
)(
    input logic clk,
    input logic rst,

    input logic write_mode,
    input logic data_valid,
    input logic [71:0] data_in,

    input logic read_mode,
    output logic data_ready,
    output logic [575:0] data_out [0:7]
);

endmodule
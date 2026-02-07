// Latency of IP = 3 cycles
module dsp_wrap_int8 (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        en,        // Clock Enable
    input  logic [7:0]  pixel_in,  // A
    input  logic [7:0]  weight_in, // B
    input  logic [31:0] acc_in,    // C
    output logic [31:0] data_out   // P[31:0]
);

    logic [47:0] p_full;
    
    mult_gen_0 i_mult_add (
        .CLK(clk),
        .CE(en),
        .SCLR(!rst_n),
        .A(pixel_in),
        .B(weight_in),
        .C(acc_in),
        .SUBTRACT(1'b0), 
        .P(p_full),
        .PCOUT()   
    );

    assign data_out = p_full[31:0];

endmodule

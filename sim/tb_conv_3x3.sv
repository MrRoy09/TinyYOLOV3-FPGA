
`timescale 1ns / 1ps

module tb_conv_3x3();

    // Parameters
    parameter WIDTH = 10; // Small width for fast simulation
    parameter CLK_PERIOD = 2.0; // 500 MHz

    // Signals
    logic clk;
    logic rst;
    logic [7:0] pixel_in;
    logic       data_valid_in;
    
    // Window outputs
    logic [7:0] window [0:2][0:2];
    logic       window_valid;
    
    // Convolution signals
    logic [7:0]  pixels_1d [0:8];
    logic [7:0]  weights [0:8];
    logic [31:0] bias;
    logic [31:0] conv_out;
    logic        conv_valid;

    // 1. Clock Generation (500 MHz)
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // 2. Mapping Window (2D) to Conv (1D)
    // kernelWindow: [row][col] where row 0 is newest (bottom)
    assign pixels_1d[0] = window[0][0]; assign pixels_1d[1] = window[0][1]; assign pixels_1d[2] = window[0][2];
    assign pixels_1d[3] = window[1][0]; assign pixels_1d[4] = window[1][1]; assign pixels_1d[5] = window[1][2];
    assign pixels_1d[6] = window[2][0]; assign pixels_1d[7] = window[2][1]; assign pixels_1d[8] = window[2][2];

    // 3. Instantiate Kernel Window
    kernelWindow #(.WIDTH(WIDTH)) dut_window (
        .clk(clk),
        .rst(rst),
        .pixel_in(pixel_in),
        .data_valid(data_valid_in),
        .window(window),
        .valid_out(window_valid)
    );

    // 4. Instantiate Conv Engine
    conv_3x3 dut_conv (
        .clk(clk),
        .rst(rst),
        .valid_in(window_valid),
        .pixels(pixels_1d),
        .weights(weights),
        .bias(bias),
        .out(conv_out),
        .data_valid(conv_valid)
    );

    // 5. Test Stimulus
    initial begin
        // Initialize
        rst = 1;
        pixel_in = 0;
        data_valid_in = 0;
        bias = 32'h00000005; // Bias of 5
        
        // Set weights to all 1s
        for (int i=0; i<9; i++) weights[i] = 8'd1;

        #(CLK_PERIOD * 10);
        rst = 0;
        #(CLK_PERIOD * 5);

        // Start streaming pixels (all value 1)
        // Total pixels to send = 4 rows (4 * 10)
        repeat (40) begin
            @(posedge clk);
            data_valid_in = 1;
            pixel_in = 8'd1;
        end

        // Stop streaming
        @(posedge clk);
        data_valid_in = 0;
        pixel_in = 0;

        // Wait for pipeline to drain
        #(CLK_PERIOD * 50);
        
        $display("Simulation Finished.");
        $finish;
    end

    // 6. Monitor
    initial begin
        $monitor("Time=%0t | ValidOut=%b | ConvOut=%d", $time, conv_valid, conv_out);
    end

endmodule

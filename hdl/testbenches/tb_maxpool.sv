`timescale 1ns / 1ps

module tb_maxpool;

    // Clock and Reset
    logic clk;
    logic rst;

    // Module Inputs
    logic [15:0] img_width;
    logic [15:0] channels;
    logic stride_2;
    logic [63:0] data_in;
    logic valid_in;

    // Module Outputs
    logic [63:0] data_out;
    logic valid_out;

    // Instantiate the Unit Under Test (UUT)
    maxPool uut (
        .clk(clk),
        .rst(rst),
        .img_width(img_width),
        .channels(channels),
        .stride_2(stride_2),
        .data_in(data_in),
        .valid_in(valid_in),
        .data_out(data_out),
        .valid_out(valid_out)
    );

    // Clock Generation (100MHz)
    always #5 clk = ~clk;

    // Helper Task to send a single "Super-Pixel" (all channels for one spatial location)
    // For 16 channels and Pin=8, this takes 2 cycles.
    task send_pixel(input [7:0] base_val);
        for (int c = 0; c < (channels >> 3); c++) begin
            @(posedge clk);
            valid_in = 1;
            for (int i = 0; i < 8; i++) begin
                // Each byte in the 64-bit word gets base_val + channel_offset
                data_in[i*8 +: 8] = base_val + (c * 8) + i;
            end
        end
        @(posedge clk);
        valid_in = 0;
        data_in = '0;
    endtask

    initial begin
        // Initialize
        clk = 0;
        rst = 1;
        valid_in = 0;
        data_in = 0;
        img_width = 4;
        channels = 16;
        stride_2 = 1; // Testing Stride 2 first

        // Reset Sequence
        #20 rst = 0;
        #20;

        $display("--- Starting MaxPool Stride 2 Test (4x4, 16 channels) ---");

        // Send a 4x4 image. 
        // We will make Pixel (1,1) have a high value to verify it's captured in the 2x2 pool.
        for (int r = 0; r < 4; r++) begin
            for (int c = 0; c < 4; c++) begin
                if (r == 1 && c == 1) 
                    send_pixel(8'd100); // High value
                else if (r == 0 && c == 0)
                    send_pixel(8'd50);  // Medium value
                else
                    send_pixel(8'd10);  // Low value
                
                // Optional: small delay between spatial pixels
                repeat(2) @(posedge clk); 
            end
        end

        // Wait for processing to finish
        #500;

        $display("--- Switching to Stride 1 Test ---");
        rst = 1;
        stride_2 = 0;
        #20 rst = 0;
        #20;

        for (int r = 0; r < 3; r++) begin
            for (int c = 0; c < 3; c++) begin
                send_pixel(8'd20 + r + c);
            end
        end

        #500;
        $display("Simulation Finished.");
        $finish;
    end

    // Simple Monitor
    always @(posedge clk) begin
        if (valid_out) begin
            $display("[%t] OUT VALID | Data: %h", $time, data_out);
        end
    end

endmodule

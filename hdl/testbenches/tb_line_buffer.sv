`timescale 1ns / 1ps

// Testbench for lineBuffer: verifies output delay matches curr_width cycles

module tb_line_buffer;

    logic        clk;
    logic        rst;
    logic [31:0] curr_width;
    logic [63:0] pixel;
    logic        data_valid;
    logic [63:0] o_data;

    lineBuffer #(
        .MAX_WIDTH(128)
    ) u_dut (
        .clk       (clk),
        .rst       (rst),
        .curr_width(curr_width),
        .pixel     (pixel),
        .data_valid(data_valid),
        .o_data    (o_data)
    );

    // Clock generation
    initial clk = 0;
    always #5 clk = ~clk;

    // Timeout
    initial begin
        #100us;
        $display("[%0t] TIMEOUT", $time);
        $finish;
    end

    int errors = 0;

    // Test a specific curr_width value
    // For curr_width=N, hardware delay is N cycles.
    // Testbench sees N+1 iteration delay (captured is 1 cycle behind due to read-before-posedge)
    task automatic test_width(input int width);
        logic [63:0] history [$];
        logic [63:0] expected;
        logic [63:0] captured_odata;
        int          i;
        int          testbench_delay;

        $display("\n--- Testing curr_width = %0d ---", width);

        // For width=1 (bypass), direct register, testbench sees 1 iteration delay
        // For width>=2, circular buffer, testbench sees width+1 iteration delay
        testbench_delay = (width <= 1) ? 1 : width + 1;

        // Reset
        rst = 1;
        data_valid = 0;
        pixel = 0;
        curr_width = width;
        repeat(3) @(posedge clk);
        rst = 0;
        repeat(2) @(posedge clk);

        // Stream values and check delay
        history = {};

        for (i = 0; i < 30; i++) begin
            // Capture o_data BEFORE changing pixel (this is output from previous cycle)
            captured_odata = o_data;

            // Check if we have enough history to verify (accounting for priming)
            if (history.size() >= testbench_delay) begin
                expected = history.pop_front();
                if (captured_odata !== expected) begin
                    $display("  ERROR at cycle %0d: got %h, expected %h", i, captured_odata, expected);
                    errors++;
                end else begin
                    $display("  OK cycle %0d: %h", i, captured_odata);
                end
            end

            // Now set new pixel and push to history
            pixel = 64'hCAFE_0000_0000_0000 | i;
            data_valid = 1;
            history.push_back(pixel);

            @(posedge clk);
        end

        // Drain remaining - continue streaming zeros to push out buffered values
        while (history.size() > 0) begin
            captured_odata = o_data;
            expected = history.pop_front();
            if (captured_odata !== expected) begin
                $display("  ERROR drain: got %h, expected %h", captured_odata, expected);
                errors++;
            end else begin
                $display("  OK drain: %h", captured_odata);
            end

            pixel = 64'h0;
            data_valid = 1;
            @(posedge clk);
        end

        data_valid = 0;

    endtask

    initial begin
        $dumpfile("tb_line_buffer.vcd");
        $dumpvars(0, tb_line_buffer);

        $display("\n=========================================");
        $display("  lineBuffer Testbench");
        $display("=========================================");

        // Test various widths
        test_width(1);   // Bypass mode
        test_width(2);   // Minimal circular buffer
        test_width(4);   // Small buffer
        test_width(8);   // Typical size
        test_width(12);  // Larger buffer

        #100;
        $display("\n=========================================");
        if (errors == 0)
            $display("  PASSED: All tests passed");
        else
            $display("  FAILED: %0d errors", errors);
        $display("=========================================\n");
        $finish;
    end

endmodule

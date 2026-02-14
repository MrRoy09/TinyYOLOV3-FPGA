`timescale 1ns / 1ps

module tb_weight_manager;

    parameter DEPTH = 4096;
    logic clk;
    logic rst;

    logic write_mode;
    logic data_valid;
    logic [71:0] data_in;
    logic write_complete;

    logic [9:0] cfg_ci_groups;
    logic [9:0] cfg_co_groups;

    logic read_en;
    logic data_ready;
    logic [575:0] data_out [0:7];
    logic read_complete;

    // cin=64, cout=128
    localparam CIN = 64;
    localparam COUT = 128;
    localparam CI_GROUPS = CIN / 8;
    localparam CO_GROUPS = COUT / 8;

    weight_manager #(
        .DEPTH(DEPTH)
    ) dut (
        .clk(clk),
        .rst(rst),
        .write_mode(write_mode),
        .data_valid(data_valid),
        .data_in(data_in),
        .write_complete(write_complete),
        .cfg_ci_groups(10'(CI_GROUPS)),
        .cfg_co_groups(10'(CO_GROUPS)),
        .read_en(read_en),
        .data_ready(data_ready),
        .data_out(data_out),
        .read_complete(read_complete)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    // Timeout logic
    initial begin
        #500us;
        $display("[%0t] ERROR: Simulation timeout!", $time);
        $finish;
    end

    // Shadow memory: [filter][channel] = 72-bit data
    logic [71:0] shadow_mem [COUT][CIN];

    initial begin
        rst = 1;
        write_mode = 0;
        data_valid = 0;
        data_in = 0;
        read_en = 0;
        cfg_ci_groups = CI_GROUPS;
        cfg_co_groups = CO_GROUPS;

        #100 rst = 0;
        #100;

        $display("[%0t] Starting Write Sequence (CIN=%0d, COUT=%0d)", $time, CIN, COUT);
        for (int f = 0; f < COUT; f++) begin
            for (int c = 0; c < CIN; c++) begin
                @(posedge clk);
                write_mode <= 1;
                data_valid <= 1;
                data_in <= {8'(f), 8'(c), 56'h11223344556677};
                shadow_mem[f][c] = {8'(f), 8'(c), 56'h11223344556677};
            end
        end
        @(posedge clk);
        data_valid <= 0;
        
        $display("[%0t] Loop finished, waiting for write_complete...", $time);
        wait(write_complete);
        $display("[%0t] Write sequence complete. write_complete ASSERTED.", $time);
        @(posedge clk);
        write_mode <= 0;
        #100;

        $display("[%0t] Starting Read and Verify", $time);
        for (int og = 0; og < CO_GROUPS; og++) begin
            for (int ig = 0; ig < CI_GROUPS; ig++) begin
                if (ig == 0 && og % 4 == 0) $display("[%0t] Verifying Filter Group %0d...", $time, og);
                
                @(posedge clk);
                read_en <= 1;
                @(posedge clk);
                read_en <= 0; 
                
                // Wait for data_ready (3 cycles latency)
                repeat(2) @(posedge clk);
                if (!data_ready) wait(data_ready);

                // Verify each of the 8 filters in the group
                for (int f_off = 0; f_off < 8; f_off++) begin
                    int f_idx = og * 8 + f_off;
                    logic [575:0] actual = data_out[f_off];
                    logic [575:0] expected;
                    
                    // Reconstruct expected 576-bit value from shadow memory
                    for (int pos = 0; pos < 9; pos++) begin
                        for (int c_off = 0; c_off < 8; c_off++) begin
                            int c_idx = ig * 8 + c_off;
                            expected[(pos*64 + c_off*8) +: 8] = shadow_mem[f_idx][c_idx][(pos*8) +: 8];
                        end
                    end

                    if (actual !== expected) begin
                        $display("[%0t] MISMATCH: Filter %0d, Channel Group %0d", $time, f_idx, ig);
                        // Detailed byte-level mismatch for debugging
                        for (int b = 0; b < 72; b++) begin
                            if (actual[b*8 +: 8] !== expected[b*8 +: 8]) begin
                                $display("  Byte %0d mismatch: exp=%h got=%h", b, expected[b*8 +: 8], actual[b*8 +: 8]);
                            end
                        end
                    end
                end
            end
        end

        wait(read_complete);
        $display("[%0t] Simulation complete SUCCESS", $time);
        $finish;
    end

endmodule

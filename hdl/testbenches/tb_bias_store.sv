module tb_bias_store;

localparam MAX_DEPTH  = 256;
localparam ADDR_WIDTH = $clog2(MAX_DEPTH);
localparam NUM_GROUPS = 4;  // test with 4 output groups = 32 biases

logic        clk, rst;
logic        wr_en;
logic [127:0] wr_data;
logic        rd_en;
logic [ADDR_WIDTH-2:0] rd_group;
logic [31:0] bias_out [0:7];
logic        rd_valid;

bias_store #(
    .MAX_DEPTH(MAX_DEPTH)
) dut (.*);

// clock
initial clk = 0;
always #5 clk = ~clk;

// expected bias values: bias[n] = n + 1
task automatic write_all_biases();
    for (int g = 0; g < NUM_GROUPS; g++) begin
        // row 0: biases [g*8 +: 4]
        for (int r = 0; r < 2; r++) begin
            logic [127:0] word;
            for (int i = 0; i < 4; i++) begin
                word[i*32 +: 32] = g * 8 + r * 4 + i + 1;
            end
            @(posedge clk);
            wr_en   <= 1;
            wr_data <= word;
        end
    end
    @(posedge clk);
    wr_en <= 0;
endtask

task automatic read_and_check(input int group);
    @(posedge clk);
    rd_en    <= 1;
    rd_group <= group;
    @(posedge clk);
    rd_en <= 0;
    @(posedge clk); // wait for rd_valid

    assert(rd_valid) else $fatal(1, "rd_valid not asserted for group %0d", group);
    for (int i = 0; i < 8; i++) begin
        int expected = group * 8 + i + 1;
        assert(bias_out[i] == expected)
            else $fatal(1, "group %0d bias[%0d]: got %0d, expected %0d",
                         group, i, bias_out[i], expected);
    end
    $display("PASS: group %0d biases = [%0d %0d %0d %0d %0d %0d %0d %0d]",
             group,
             bias_out[0], bias_out[1], bias_out[2], bias_out[3],
             bias_out[4], bias_out[5], bias_out[6], bias_out[7]);
endtask

initial begin
    $dumpfile("tb_bias_store.vcd");
    $dumpvars(0, tb_bias_store);

    rst     = 1;
    wr_en   = 0;
    rd_en   = 0;
    rd_group = 0;
    wr_data = 0;

    repeat(3) @(posedge clk);
    rst = 0;
    @(posedge clk);

    // write all biases
    $display("--- Writing %0d groups (%0d biases) ---", NUM_GROUPS, NUM_GROUPS * 8);
    write_all_biases();
    repeat(2) @(posedge clk);

    // read back each group and verify
    $display("--- Reading back ---");
    for (int g = 0; g < NUM_GROUPS; g++) begin
        read_and_check(g);
    end

    // read out of order
    $display("--- Out-of-order reads ---");
    read_and_check(3);
    read_and_check(0);
    read_and_check(2);
    read_and_check(1);

    $display("ALL TESTS PASSED");
    $finish;
end

endmodule

module lineBuffer #(
    parameter MAX_WIDTH = 8192 // Fixed physical size
)(
    input  logic        clk,
    input  logic        rst,
    input  logic [31:0] curr_width, // Dynamic reset point (e.g., width * channels)
    input  logic [63:0]  pixel,
    input  logic        data_valid,
    output logic [63:0]  o_data
);

    // ═══════════════════════════════════════════════════════════════════════
    // Local config register - break timing path for curr_width comparison
    // curr_width is stable before processing, so registering is safe.
    // ═══════════════════════════════════════════════════════════════════════
    (* max_fanout = 32 *) logic [31:0] curr_width_r;

    always_ff @(posedge clk) begin
        if (rst)
            curr_width_r <= '0;
        else
            curr_width_r <= curr_width;
    end

    // Attribute to force Block RAM implementation
    (* ram_style = "block" *)
    logic [63:0] line [MAX_WIDTH-1:0];

    initial begin
        for (int i = 0; i < MAX_WIDTH; i++) begin
            line[i] = '0;
        end
    end

    // Pointer width must match MAX_WIDTH
    logic [$clog2(MAX_WIDTH)-1:0] wrPtr;

    always_ff @(posedge clk) begin
        if (rst) begin
            wrPtr  <= '0;
            o_data <= '0;
        end else if (data_valid) begin
            if (curr_width_r <= 1) begin
                // Bypass: just a register = 1 cycle delay
                o_data <= pixel;
            end else begin
                // Circular buffer with curr_width entries, read-before-write
                // Input at cycle N appears at output at cycle N+curr_width
                o_data <= line[wrPtr];
                line[wrPtr] <= pixel;

                if (wrPtr >= curr_width_r - 1)
                    wrPtr <= '0;
                else
                    wrPtr <= wrPtr + 1'b1;
            end
        end
    end

endmodule

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

    // Attribute to force Block RAM implementation
    (* ram_style = "block" *) 
    logic [63:0] line [MAX_WIDTH-1:0]; 

    // Pointer width must match MAX_WIDTH
    logic [$clog2(MAX_WIDTH)-1:0] wrPtr; 

    always_ff @(posedge clk) begin
        if (rst) begin
            wrPtr  <= '0;
            o_data <= '0;
        end else if (data_valid) begin
            // Read old pixel (from previous row)
            o_data <= line[wrPtr];
            // Store new pixel (for next row)
            line[wrPtr] <= pixel;
            
            // Pointer increment with dynamic wrap-around
            if (wrPtr >= curr_width - 1) 
                wrPtr <= '0;
            else 
                wrPtr <= wrPtr + 1'b1;
        end
    end

endmodule
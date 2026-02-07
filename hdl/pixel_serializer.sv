
module pixel_serializer #(
    parameter AXIS_WIDTH = 512,
    parameter PIXEL_WIDTH = 8
)(
    input  logic                   clk,
    input  logic                   rst,
    
    // AXI-Stream Slave (512-bit)
    input  logic [AXIS_WIDTH-1:0]  s_axis_tdata,
    input  logic                   s_axis_tvalid,
    output logic                   s_axis_tready,
    
    // Serialized Pixel Output (8-bit)
    output logic [PIXEL_WIDTH-1:0] pixel_out,
    output logic                   pixel_valid,
    input  logic                   pixel_ready // From downstream kernelWindow
);

    localparam PIXELS_PER_CHUNK = AXIS_WIDTH / PIXEL_WIDTH; // 64

    logic [AXIS_WIDTH-1:0] shift_reg;
    logic [5:0]            count; // 0 to 63
    
    typedef enum logic {IDLE, SHIFTING} state_t;
    state_t state;

    // We are ready for a new 512-bit chunk only when IDLE
    assign s_axis_tready = (state == IDLE);

    always_ff @(posedge clk) begin
        if (rst) begin
            state       <= IDLE;
            shift_reg   <= '0;
            count       <= '0;
            pixel_out   <= '0;
            pixel_valid <= 1'b0;
        end else begin
            case (state)
                IDLE: begin
                    pixel_valid <= 1'b0;
                    if (s_axis_tvalid && s_axis_tready) begin
                        shift_reg <= s_axis_tdata;
                        state     <= SHIFTING;
                        count     <= '0;
                    end
                end

                SHIFTING: begin
                    if (pixel_ready) begin
                        // Output the current bottom 8 bits
                        pixel_out   <= shift_reg[7:0];
                        pixel_valid <= 1'b1;
                        
                        // Shift the register
                        shift_reg <= shift_reg >> PIXEL_WIDTH;
                        
                        if (count == PIXELS_PER_CHUNK - 1) begin
                            state <= IDLE;
                        end else begin
                            count <= count + 1'b1;
                        end
                    end else begin
                        // If downstream isn't ready, we hold our valid high but don't shift
                        pixel_valid <= 1'b1;
                    end
                end
            endcase
        end
    end

endmodule

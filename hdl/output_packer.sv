
module output_packer #(
    parameter NUM_FILTERS = 64,
    parameter AXIS_WIDTH  = 512
)(
    input  logic                   clk,
    input  logic                   rst,
    
    // Parallel inputs from 64 Quantizers
    input  logic [7:0]             pixel_results [0:NUM_FILTERS-1],
    input  logic                   valid_in,
    output logic                   ready_out, // Back-pressure to compute engines
    
    // AXI-Stream Master (512-bit)
    output logic [AXIS_WIDTH-1:0]  m_axis_tdata,
    output logic                   m_axis_tvalid,
    input  logic                   m_axis_tready,
    output logic                   m_axis_tlast // Pass-through from controller
);

    // Internal packed wire
    logic [AXIS_WIDTH-1:0] packed_data;
    
    // Pack the 64 filters into the 512-bit bus
    // Filter 0 at bits [7:0], Filter 1 at [15:8], etc.
    always_comb begin
        for (int i = 0; i < NUM_FILTERS; i++) begin
            packed_data[i*8 +: 8] = pixel_results[i];
        end
    end

    // Simple Skid Buffer / Output Register for timing closure at 500MHz
    // This ensures that the massive 512-bit bus is registered right before the pins.
    always_ff @(posedge clk) begin
        if (rst) begin
            m_axis_tdata  <= '0;
            m_axis_tvalid <= 1'b0;
        end else begin
            if (m_axis_tready || !m_axis_tvalid) begin
                m_axis_tdata  <= packed_data;
                m_axis_tvalid <= valid_in;
            end
        end
    end

    // We are ready for more data if the output is ready or empty
    assign ready_out = m_axis_tready || !m_axis_tvalid;

endmodule

// This is a generated file. Use and modify at your own risk.
//////////////////////////////////////////////////////////////////////////////// 
// default_nettype of none prevents implicit wire declaration.
`default_nettype none
module TinyYOLOHW_example #(
  parameter integer C_AXI_IN_TDATA_WIDTH  = 512,
  parameter integer C_AXI_OUT_TDATA_WIDTH = 512
)
(
  // System Signals
  input  wire                               ap_clk        ,
  input  wire                               ap_rst_n      ,
  input  wire                               ap_clk_2      ,
  input  wire                               ap_rst_n_2    ,
  // Pipe (AXI4-Stream host) interface axi_in
  input  wire                               axi_in_tvalid ,
  output wire                               axi_in_tready ,
  input  wire [C_AXI_IN_TDATA_WIDTH-1:0]    axi_in_tdata  ,
  input  wire [C_AXI_IN_TDATA_WIDTH/8-1:0]  axi_in_tkeep  ,
  input  wire                               axi_in_tlast  ,
  // Pipe (AXI4-Stream host) interface axi_out
  output wire                               axi_out_tvalid,
  input  wire                               axi_out_tready,
  output wire [C_AXI_OUT_TDATA_WIDTH-1:0]   axi_out_tdata ,
  output wire [C_AXI_OUT_TDATA_WIDTH/8-1:0] axi_out_tkeep ,
  output wire                               axi_out_tlast ,
  // Control Signals
  input  wire                               ap_start      ,
  output wire                               ap_idle       ,
  output wire                               ap_done       ,
  output wire                               ap_ready      ,
  input  wire [32-1:0]                      img_width     ,
  input  wire [32-1:0]                      in_channels   ,
  input  wire [32-1:0]                      out_channels  ,
  input  wire [32-1:0]                      quant_M       ,
  input  wire [32-1:0]                      quant_n       ,
  input  wire                               isMaxpool     ,
  input  wire                               is_1x1        ,
  input  wire [32-1:0]                      stride        
);


timeunit 1ps;
timeprecision 1ps;

///////////////////////////////////////////////////////////////////////////////
// Local Parameters
///////////////////////////////////////////////////////////////////////////////
// Large enough for interesting traffic.
localparam integer  LP_DEFAULT_LENGTH_IN_BYTES = 16384;
localparam integer  LP_NUM_EXAMPLES    = 1;

///////////////////////////////////////////////////////////////////////////////
// Wires and Variables
///////////////////////////////////////////////////////////////////////////////
(* KEEP = "yes" *)
logic                                areset                         = 1'b0;
logic                                kernel_rst                     = 1'b0;
logic                                kernel_rst_2                   = 1'b0;
logic                                ap_start_r                     = 1'b0;
logic                                ap_idle_r                      = 1'b1;
logic                                ap_start_pulse                ;
logic [LP_NUM_EXAMPLES-1:0]          ap_done_i                     ;
logic [LP_NUM_EXAMPLES-1:0]          ap_done_r                      = {LP_NUM_EXAMPLES{1'b0}};
logic [32-1:0]                       ctrl_xfer_size_in_bytes        = LP_DEFAULT_LENGTH_IN_BYTES;
logic [32-1:0]                       ctrl_constant                  = 32'd1;

///////////////////////////////////////////////////////////////////////////////
// Begin RTL
///////////////////////////////////////////////////////////////////////////////

// Register and invert reset signal.
always @(posedge ap_clk) begin
  areset <= ~ap_rst_n;
end

// create pulse when ap_start transitions to 1
always @(posedge ap_clk) begin
  begin
    ap_start_r <= ap_start;
  end
end

assign ap_start_pulse = ap_start & ~ap_start_r;

// ap_idle is asserted when done is asserted, it is de-asserted when ap_start_pulse
// is asserted
always @(posedge ap_clk) begin
  if (areset) begin
    ap_idle_r <= 1'b1;
  end
  else begin
    ap_idle_r <= ap_done ? 1'b1 :
      ap_start_pulse ? 1'b0 : ap_idle;
  end
end

assign ap_idle = ap_idle_r;

// Done logic
always @(posedge ap_clk) begin
  if (areset) begin
    ap_done_r <= '0;
  end
  else begin
    ap_done_r <= (ap_done) ? '0 : ap_done_r | ap_done_i;
  end
end

assign ap_done = &ap_done_r;

// Ready Logic (non-pipelined case)
assign ap_ready = ap_done;


// Register and invert kernel reset signal.
always @(posedge ap_clk_2) begin
  kernel_rst <= ~ap_rst_n_2;
end



// Register and invert kernel reset signal.
always @(posedge ap_clk_2) begin
  kernel_rst_2 <= ~ap_rst_n_2;
end

// Vadd stream example (Now our TinyYOLO Compute Engine)
TinyYOLOHW_example_vadd_axis #(
  .C_S_AXIS_TDATA_WIDTH ( C_AXI_OUT_TDATA_WIDTH      ),
  .C_M_AXIS_TDATA_WIDTH ( C_AXI_OUT_TDATA_WIDTH      ),
  .C_ADDER_BIT_WIDTH    ( 32                         ),
  .C_NUM_CLOCKS         ( 2                          ),
  .C_GEN_S_AXIS_DATA    ( 0                          ),
  .C_LENGTH_IN_BYTES    ( LP_DEFAULT_LENGTH_IN_BYTES )
)
inst_example_vadd__axi_in_to_axi_out (
  .aclk          ( ap_clk         ),
  .areset        ( areset         ),
  .kernel_clk    ( ap_clk_2       ),
  .kernel_rst    ( kernel_rst     ),
  .s_axis_tvalid ( axi_in_tvalid  ),
  .s_axis_tready ( axi_in_tready  ),
  .s_axis_tdata  ( axi_in_tdata   ),
  .s_axis_tkeep  ( axi_in_tkeep   ),
  .s_axis_tlast  ( axi_in_tlast   ),
  .m_axis_tvalid ( axi_out_tvalid ),
  .m_axis_tready ( axi_out_tready ),
  .m_axis_tdata  ( axi_out_tdata  ),
  .m_axis_tkeep  ( axi_out_tkeep  ),
  .m_axis_tlast  ( axi_out_tlast  ),
  
  // Connect scalar parameters
  .img_width     ( img_width      ),
  .in_channels   ( in_channels    ),
  .out_channels  ( out_channels   ),
  .quant_M       ( quant_M        ),
  .quant_n       ( quant_n        ),
  .is_maxpool    ( isMaxpool      ),
  .is_1x1        ( is_1x1         ),
  .stride        ( stride         ),

  .ctrl_constant ( 32'b1          ),
  .ap_start      ( ap_start_pulse ),
  .ap_idle       ( ap_idle        ),
  .ap_done       ( ap_done_i[0]   )
);

endmodule : TinyYOLOHW_example
`default_nettype wire
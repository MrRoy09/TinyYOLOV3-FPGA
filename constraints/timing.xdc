# Clock constraint for conv_top
# Target: 140 MHz (7.143 ns period)
# Note: 150 MHz had WNS=-0.084ns (13 logic levels in conv_pe adder tree)
create_clock -period 7.143 -name clk [get_ports clk]

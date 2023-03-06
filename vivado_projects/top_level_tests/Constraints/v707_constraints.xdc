## Clock signal(s)
set_property -dict {PACKAGE_PIN E19 IOSTANDARD LVDS} [get_ports clk_in1_p]
set_property -dict {PACKAGE_PIN E18 IOSTANDARD LVDS} [get_ports clk_in1_n]

# UART pins
set_property -dict {PACKAGE_PIN AU36 IOSTANDARD LVCMOS18} [get_ports tx_output]
set_property -dict {PACKAGE_PIN AU33 IOSTANDARD LVCMOS18} [get_ports rx_input]
#set_property -dict {PACKAGE_PIN AR34 IOSTANDARD LVCMOS18} [get_ports rts_output]
#set_property -dict {PACKAGE_PIN AT32 IOSTANDARD LVCMOS18} [get_ports cts_input]

# Reset Switch
set_property -dict {PACKAGE_PIN AP40 IOSTANDARD LVCMOS18} [get_ports rst]


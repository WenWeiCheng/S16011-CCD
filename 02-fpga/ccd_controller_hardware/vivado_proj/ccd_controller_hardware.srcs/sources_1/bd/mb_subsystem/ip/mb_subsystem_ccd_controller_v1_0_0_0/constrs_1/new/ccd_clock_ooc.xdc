create_clock -period 10.000 -name axi_clk -waveform {0.000 5.000} [get_ports s00_axi_aclk]
create_clock -period 10.000 -name ddr_ui_clk -waveform {0.000 5.000} [get_ports i_ui_clk]
create_clock -period 20.833 -name rd_clk -waveform {0.000 10.417} [get_ports i_rd_clk]
create_clock -period 20.833 -name rd_clk_n -waveform {10.417 20.833} [get_ports i_rd_clk_n]

create_generated_clock -name ccd_sclk_p180 -source [get_ports s00_axi_aclk] -edges {1 2 3} -edge_shift {1000.000 2000.000 3000.000} [get_pins -hierarchical -regexp -nocase .*sclk_p180_reg/Q.*]
create_generated_clock -name ccd_sclk_p90 -source [get_ports s00_axi_aclk] -edges {1 2 3} -edge_shift {500.000 1500.000 2500.000} [get_pins ccd_controller_v1_0_S00_AXI_inst/u_ccd_ddr/u_ccd_driver/u_ccd_clk_gen/o_sclk_p90_reg/Q]
create_generated_clock -name ccd_sclk_p0 -source [get_ports s00_axi_aclk] -edges {1 2 3} -edge_shift {0.000 1000.000 2000.000} [get_pins ccd_controller_v1_0_S00_AXI_inst/u_ccd_ddr/u_ccd_driver/u_ccd_clk_gen/o_sclk_p0_reg/Q]
create_generated_clock -name ccd_sclk_p270 -source [get_ports s00_axi_aclk] -edges {1 2 3} -edge_shift {1500.000 2500.000 3500.000} [get_pins ccd_controller_v1_0_S00_AXI_inst/u_ccd_ddr/u_ccd_driver/u_ccd_clk_gen/o_sclk_p270_reg/Q]

set_clock_groups -name async_clk_group -asynchronous -group [get_clocks axi_clk] -group [get_clocks ddr_ui_clk] -group [get_clocks {ccd_sclk_p0 ccd_sclk_p90 ccd_sclk_p180 ccd_sclk_p270}] -group [get_clocks {rd_clk rd_clk_n}]
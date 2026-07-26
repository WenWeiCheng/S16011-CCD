create_clock -period 10.000 -name i_clk -waveform {0.000 5.000} [get_ports i_clk]
create_clock -period 5.000 -name i_ddr3_clk200m_ref -waveform {0.000 2.500} [get_ports i_ddr3_clk200m_ref]
create_clock -period 20.833 -name i_rd_clk -waveform {0.000 10.417} [get_ports i_rd_clk]






create_generated_clock -name u_ccd_driver/u_ccd_clk_gen/o_sclk_p180_reg/Q -source [get_ports i_clk] -edges {1 2 3} -edge_shift {1000.000 2000.000 3000.000} [get_pins u_ccd_driver/u_ccd_clk_gen/o_sclk_p180_reg/Q]
create_generated_clock -name u_ccd_driver/u_ccd_clk_gen/o_sclk_p90_reg/Q -source [get_ports i_clk] -edges {1 2 3} -edge_shift {500.000 1500.000 2500.000} [get_pins u_ccd_driver/u_ccd_clk_gen/o_sclk_p90_reg/Q]
create_generated_clock -name u_ccd_driver/u_ccd_clk_gen/o_sclk_p270_reg/Q -source [get_ports i_clk] -edges {1 2 3} -edge_shift {1500.000 2500.000 3500.000} [get_pins u_ccd_driver/u_ccd_clk_gen/o_sclk_p270_reg/Q]
create_generated_clock -name u_ccd_driver/u_ccd_clk_gen/o_sclk_p0_reg/Q -source [get_ports i_clk] -edges {1 2 3} -edge_shift {0.000 1000.000 2000.000} [get_pins u_ccd_driver/u_ccd_clk_gen/o_sclk_p0_reg/Q]
set_clock_groups -name async_clk_group -asynchronous -group [get_clocks i_clk] -group [get_clocks i_ddr3_clk200m_ref] -group [get_clocks -of_objects [get_pins u_ccd_frame_buf_ddr/u_mig/u_mig_7series_0_mig/u_ddr3_infrastructure/gen_mmcm.mmcm_i/CLKFBOUT]] -group [get_clocks i_rd_clk] -group [get_clocks *sclk_p*]

set_false_path -to [get_pins -hierarchical *dq_i/RST*]
set_false_path -from [get_pins {u_ccd_frame_buf_ddr/u_mig/u_mig_7series_0_mig/u_memc_ui_top_axi/mem_intfc0/ddr_phy_top0/u_ddr_mc_phy_wrapper/u_ddr_mc_phy/ddr_phy_4lanes_0.u_ddr_phy_4lanes/ddr_byte_lane_A.ddr_byte_lane_A/phaser_out/OCLK u_ccd_frame_buf_ddr/u_mig/u_mig_7series_0_mig/u_memc_ui_top_axi/mem_intfc0/ddr_phy_top0/u_ddr_mc_phy_wrapper/u_ddr_mc_phy/ddr_phy_4lanes_0.u_ddr_phy_4lanes/ddr_byte_lane_B.ddr_byte_lane_B/phaser_out/OCLK u_ccd_frame_buf_ddr/u_mig/u_mig_7series_0_mig/u_memc_ui_top_axi/mem_intfc0/ddr_phy_top0/u_ddr_mc_phy_wrapper/u_ddr_mc_phy/ddr_phy_4lanes_0.u_ddr_phy_4lanes/ddr_byte_lane_C.ddr_byte_lane_C/phaser_out/OCLK u_ccd_frame_buf_ddr/u_mig/u_mig_7series_0_mig/u_memc_ui_top_axi/mem_intfc0/ddr_phy_top0/u_ddr_mc_phy_wrapper/u_ddr_mc_phy/ddr_phy_4lanes_0.u_ddr_phy_4lanes/ddr_byte_lane_D.ddr_byte_lane_D/phaser_out/OCLK u_ccd_frame_buf_ddr/u_mig/u_mig_7series_0_mig/u_memc_ui_top_axi/mem_intfc0/ddr_phy_top0/u_ddr_mc_phy_wrapper/u_ddr_mc_phy/ddr_phy_4lanes_1.u_ddr_phy_4lanes/ddr_byte_lane_B.ddr_byte_lane_B/phaser_out/OCLK u_ccd_frame_buf_ddr/u_mig/u_mig_7series_0_mig/u_memc_ui_top_axi/mem_intfc0/ddr_phy_top0/u_ddr_mc_phy_wrapper/u_ddr_mc_phy/ddr_phy_4lanes_1.u_ddr_phy_4lanes/ddr_byte_lane_C.ddr_byte_lane_C/phaser_out/OCLK u_ccd_frame_buf_ddr/u_mig/u_mig_7series_0_mig/u_memc_ui_top_axi/mem_intfc0/ddr_phy_top0/u_ddr_mc_phy_wrapper/u_ddr_mc_phy/ddr_phy_4lanes_1.u_ddr_phy_4lanes/ddr_byte_lane_D.ddr_byte_lane_D/phaser_out/OCLK}] -to [get_pins -hierarchical *out_fifo/RDEN*]

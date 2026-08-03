// Copyright 1986-2020 Xilinx, Inc. All Rights Reserved.
// --------------------------------------------------------------------------------
// Tool Version: Vivado v.2020.1 (win64) Build 2902540 Wed May 27 19:54:49 MDT 2020
// Date        : Sat Aug  1 17:41:06 2026
// Host        : DESKTOP-KD2H86C running 64-bit major release  (build 9200)
// Command     : write_verilog -force -mode synth_stub
//               d:/2607-Pro-S16011-CCD/02-fpga/ccd_controller_hardware/vivado_proj/ccd_controller_hardware.srcs/sources_1/bd/mb_subsystem/ip/mb_subsystem_clk_wiz_0_1/mb_subsystem_clk_wiz_0_1_stub.v
// Design      : mb_subsystem_clk_wiz_0_1
// Purpose     : Stub declaration of top-level module interface
// Device      : xc7a100tfgg484-2
// --------------------------------------------------------------------------------

// This empty module with port declaration file causes synthesis tools to infer a black box for IP.
// The synthesis directives are for Synopsys Synplify support to prevent IO buffer insertion.
// Please paste the declaration into a Verilog source file or add the file as an additional source.
module mb_subsystem_clk_wiz_0_1(clk_100M, clk_200M, clk_48M, clk_48M_p180, reset, 
  locked, clk_in1)
/* synthesis syn_black_box black_box_pad_pin="clk_100M,clk_200M,clk_48M,clk_48M_p180,reset,locked,clk_in1" */;
  output clk_100M;
  output clk_200M;
  output clk_48M;
  output clk_48M_p180;
  input reset;
  output locked;
  input clk_in1;
endmodule

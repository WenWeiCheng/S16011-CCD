// Copyright 1986-2020 Xilinx, Inc. All Rights Reserved.
// --------------------------------------------------------------------------------
// Tool Version: Vivado v.2020.1 (win64) Build 2902540 Wed May 27 19:54:49 MDT 2020
// Date        : Thu Aug  6 19:15:38 2026
// Host        : DESKTOP-KD2H86C running 64-bit major release  (build 9200)
// Command     : write_verilog -force -mode synth_stub -rename_top mb_subsystem_system_ila_0_0 -prefix
//               mb_subsystem_system_ila_0_0_ mb_subsystem_system_ila_0_0_stub.v
// Design      : mb_subsystem_system_ila_0_0
// Purpose     : Stub declaration of top-level module interface
// Device      : xc7a100tfgg484-2
// --------------------------------------------------------------------------------

// This empty module with port declaration file causes synthesis tools to infer a black box for IP.
// The synthesis directives are for Synopsys Synplify support to prevent IO buffer insertion.
// Please paste the declaration into a Verilog source file or add the file as an additional source.
(* X_CORE_INFO = "bd_9912,Vivado 2020.1" *)
module mb_subsystem_system_ila_0_0(clk, probe0)
/* synthesis syn_black_box black_box_pad_pin="clk,probe0[0:0]" */;
  input clk;
  input [0:0]probe0;
endmodule

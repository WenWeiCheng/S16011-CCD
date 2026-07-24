//Copyright 1986-2020 Xilinx, Inc. All Rights Reserved.
//--------------------------------------------------------------------------------
//Tool Version: Vivado v.2020.1 (win64) Build 2902540 Wed May 27 19:54:49 MDT 2020
//Date        : Thu Jul 23 11:43:53 2026
//Host        : DESKTOP-KD2H86C running 64-bit major release  (build 9200)
//Command     : generate_target mb_subsystem_wrapper.bd
//Design      : mb_subsystem_wrapper
//Purpose     : IP block netlist
//--------------------------------------------------------------------------------
`timescale 1 ps / 1 ps

module mb_subsystem_wrapper
   (clk_50MHz,
    gpio_rtl_0_tri_o,
    reset_rtl_0,
    uart_rtl_0_rxd,
    uart_rtl_0_txd);
  input clk_50MHz;
  output [1:0]gpio_rtl_0_tri_o;
  input reset_rtl_0;
  input uart_rtl_0_rxd;
  output uart_rtl_0_txd;

  wire clk_50MHz;
  wire [1:0]gpio_rtl_0_tri_o;
  wire reset_rtl_0;
  wire uart_rtl_0_rxd;
  wire uart_rtl_0_txd;

  mb_subsystem mb_subsystem_i
       (.clk_50MHz(clk_50MHz),
        .gpio_rtl_0_tri_o(gpio_rtl_0_tri_o),
        .reset_rtl_0(reset_rtl_0),
        .uart_rtl_0_rxd(uart_rtl_0_rxd),
        .uart_rtl_0_txd(uart_rtl_0_txd));
endmodule

//Copyright 1986-2020 Xilinx, Inc. All Rights Reserved.
//--------------------------------------------------------------------------------
//Tool Version: Vivado v.2020.1 (win64) Build 2902540 Wed May 27 19:54:49 MDT 2020
//Date        : Sat Aug  8 14:42:29 2026
//Host        : DESKTOP-KD2H86C running 64-bit major release  (build 9200)
//Command     : generate_target mb_subsystem_wrapper.bd
//Design      : mb_subsystem_wrapper
//Purpose     : IP block netlist
//--------------------------------------------------------------------------------
`timescale 1 ps / 1 ps

module mb_subsystem_wrapper
   (DDR3_addr,
    DDR3_ba,
    DDR3_cas_n,
    DDR3_ck_n,
    DDR3_ck_p,
    DDR3_cke,
    DDR3_cs_n,
    DDR3_dm,
    DDR3_dq,
    DDR3_dqs_n,
    DDR3_dqs_p,
    DDR3_odt,
    DDR3_ras_n,
    DDR3_reset_n,
    DDR3_we_n,
    clk_50MHz,
    gpio_fx2_fifo_tri_io,
    gpio_general_tri_io,
    gpio_key_tri_i,
    gpio_led_tri_o,
    i_adc_data,
    i_slave_fifo_empty_n,
    i_slave_fifo_full_n,
    iic_scl_io,
    iic_sda_io,
    o_adcclk,
    o_cdsclk1,
    o_cdsclk2,
    o_p1h,
    o_p1v,
    o_p2h,
    o_p2v_tg,
    o_p3h,
    o_p4h_sg,
    o_rg,
    o_slave_fifo_clk,
    o_slave_fifo_data,
    o_slave_fifo_data_last_n,
    o_slave_fifo_data_wr_en_n,
    reset,
    spi_io0_io,
    spi_io1_io,
    spi_sck_io,
    spi_ss_io,
    uart_rxd,
    uart_txd);
  output [14:0]DDR3_addr;
  output [2:0]DDR3_ba;
  output DDR3_cas_n;
  output [0:0]DDR3_ck_n;
  output [0:0]DDR3_ck_p;
  output [0:0]DDR3_cke;
  output [0:0]DDR3_cs_n;
  output [3:0]DDR3_dm;
  inout [31:0]DDR3_dq;
  inout [3:0]DDR3_dqs_n;
  inout [3:0]DDR3_dqs_p;
  output [0:0]DDR3_odt;
  output DDR3_ras_n;
  output DDR3_reset_n;
  output DDR3_we_n;
  input clk_50MHz;
  inout [4:0]gpio_fx2_fifo_tri_io;
  inout [3:0]gpio_general_tri_io;
  input [3:0]gpio_key_tri_i;
  output [3:0]gpio_led_tri_o;
  input [7:0]i_adc_data;
  input i_slave_fifo_empty_n;
  input i_slave_fifo_full_n;
  inout iic_scl_io;
  inout iic_sda_io;
  output o_adcclk;
  output o_cdsclk1;
  output o_cdsclk2;
  output o_p1h;
  output o_p1v;
  output o_p2h;
  output o_p2v_tg;
  output o_p3h;
  output o_p4h_sg;
  output o_rg;
  output o_slave_fifo_clk;
  output [15:0]o_slave_fifo_data;
  output o_slave_fifo_data_last_n;
  output o_slave_fifo_data_wr_en_n;
  input reset;
  inout spi_io0_io;
  inout spi_io1_io;
  inout spi_sck_io;
  inout [2:0]spi_ss_io;
  input uart_rxd;
  output uart_txd;

  wire [14:0]DDR3_addr;
  wire [2:0]DDR3_ba;
  wire DDR3_cas_n;
  wire [0:0]DDR3_ck_n;
  wire [0:0]DDR3_ck_p;
  wire [0:0]DDR3_cke;
  wire [0:0]DDR3_cs_n;
  wire [3:0]DDR3_dm;
  wire [31:0]DDR3_dq;
  wire [3:0]DDR3_dqs_n;
  wire [3:0]DDR3_dqs_p;
  wire [0:0]DDR3_odt;
  wire DDR3_ras_n;
  wire DDR3_reset_n;
  wire DDR3_we_n;
  wire clk_50MHz;
  wire [0:0]gpio_fx2_fifo_tri_i_0;
  wire [1:1]gpio_fx2_fifo_tri_i_1;
  wire [2:2]gpio_fx2_fifo_tri_i_2;
  wire [3:3]gpio_fx2_fifo_tri_i_3;
  wire [4:4]gpio_fx2_fifo_tri_i_4;
  wire [0:0]gpio_fx2_fifo_tri_io_0;
  wire [1:1]gpio_fx2_fifo_tri_io_1;
  wire [2:2]gpio_fx2_fifo_tri_io_2;
  wire [3:3]gpio_fx2_fifo_tri_io_3;
  wire [4:4]gpio_fx2_fifo_tri_io_4;
  wire [0:0]gpio_fx2_fifo_tri_o_0;
  wire [1:1]gpio_fx2_fifo_tri_o_1;
  wire [2:2]gpio_fx2_fifo_tri_o_2;
  wire [3:3]gpio_fx2_fifo_tri_o_3;
  wire [4:4]gpio_fx2_fifo_tri_o_4;
  wire [0:0]gpio_fx2_fifo_tri_t_0;
  wire [1:1]gpio_fx2_fifo_tri_t_1;
  wire [2:2]gpio_fx2_fifo_tri_t_2;
  wire [3:3]gpio_fx2_fifo_tri_t_3;
  wire [4:4]gpio_fx2_fifo_tri_t_4;
  wire [0:0]gpio_general_tri_i_0;
  wire [1:1]gpio_general_tri_i_1;
  wire [2:2]gpio_general_tri_i_2;
  wire [3:3]gpio_general_tri_i_3;
  wire [0:0]gpio_general_tri_io_0;
  wire [1:1]gpio_general_tri_io_1;
  wire [2:2]gpio_general_tri_io_2;
  wire [3:3]gpio_general_tri_io_3;
  wire [0:0]gpio_general_tri_o_0;
  wire [1:1]gpio_general_tri_o_1;
  wire [2:2]gpio_general_tri_o_2;
  wire [3:3]gpio_general_tri_o_3;
  wire [0:0]gpio_general_tri_t_0;
  wire [1:1]gpio_general_tri_t_1;
  wire [2:2]gpio_general_tri_t_2;
  wire [3:3]gpio_general_tri_t_3;
  wire [3:0]gpio_key_tri_i;
  wire [3:0]gpio_led_tri_o;
  wire [7:0]i_adc_data;
  wire i_slave_fifo_empty_n;
  wire i_slave_fifo_full_n;
  wire iic_scl_i;
  wire iic_scl_io;
  wire iic_scl_o;
  wire iic_scl_t;
  wire iic_sda_i;
  wire iic_sda_io;
  wire iic_sda_o;
  wire iic_sda_t;
  wire o_adcclk;
  wire o_cdsclk1;
  wire o_cdsclk2;
  wire o_p1h;
  wire o_p1v;
  wire o_p2h;
  wire o_p2v_tg;
  wire o_p3h;
  wire o_p4h_sg;
  wire o_rg;
  wire o_slave_fifo_clk;
  wire [15:0]o_slave_fifo_data;
  wire o_slave_fifo_data_last_n;
  wire o_slave_fifo_data_wr_en_n;
  wire reset;
  wire spi_io0_i;
  wire spi_io0_io;
  wire spi_io0_o;
  wire spi_io0_t;
  wire spi_io1_i;
  wire spi_io1_io;
  wire spi_io1_o;
  wire spi_io1_t;
  wire spi_sck_i;
  wire spi_sck_io;
  wire spi_sck_o;
  wire spi_sck_t;
  wire [0:0]spi_ss_i_0;
  wire [1:1]spi_ss_i_1;
  wire [2:2]spi_ss_i_2;
  wire [0:0]spi_ss_io_0;
  wire [1:1]spi_ss_io_1;
  wire [2:2]spi_ss_io_2;
  wire [0:0]spi_ss_o_0;
  wire [1:1]spi_ss_o_1;
  wire [2:2]spi_ss_o_2;
  wire spi_ss_t;
  wire uart_rxd;
  wire uart_txd;

  IOBUF gpio_fx2_fifo_tri_iobuf_0
       (.I(gpio_fx2_fifo_tri_o_0),
        .IO(gpio_fx2_fifo_tri_io[0]),
        .O(gpio_fx2_fifo_tri_i_0),
        .T(gpio_fx2_fifo_tri_t_0));
  IOBUF gpio_fx2_fifo_tri_iobuf_1
       (.I(gpio_fx2_fifo_tri_o_1),
        .IO(gpio_fx2_fifo_tri_io[1]),
        .O(gpio_fx2_fifo_tri_i_1),
        .T(gpio_fx2_fifo_tri_t_1));
  IOBUF gpio_fx2_fifo_tri_iobuf_2
       (.I(gpio_fx2_fifo_tri_o_2),
        .IO(gpio_fx2_fifo_tri_io[2]),
        .O(gpio_fx2_fifo_tri_i_2),
        .T(gpio_fx2_fifo_tri_t_2));
  IOBUF gpio_fx2_fifo_tri_iobuf_3
       (.I(gpio_fx2_fifo_tri_o_3),
        .IO(gpio_fx2_fifo_tri_io[3]),
        .O(gpio_fx2_fifo_tri_i_3),
        .T(gpio_fx2_fifo_tri_t_3));
  IOBUF gpio_fx2_fifo_tri_iobuf_4
       (.I(gpio_fx2_fifo_tri_o_4),
        .IO(gpio_fx2_fifo_tri_io[4]),
        .O(gpio_fx2_fifo_tri_i_4),
        .T(gpio_fx2_fifo_tri_t_4));
  IOBUF gpio_general_tri_iobuf_0
       (.I(gpio_general_tri_o_0),
        .IO(gpio_general_tri_io[0]),
        .O(gpio_general_tri_i_0),
        .T(gpio_general_tri_t_0));
  IOBUF gpio_general_tri_iobuf_1
       (.I(gpio_general_tri_o_1),
        .IO(gpio_general_tri_io[1]),
        .O(gpio_general_tri_i_1),
        .T(gpio_general_tri_t_1));
  IOBUF gpio_general_tri_iobuf_2
       (.I(gpio_general_tri_o_2),
        .IO(gpio_general_tri_io[2]),
        .O(gpio_general_tri_i_2),
        .T(gpio_general_tri_t_2));
  IOBUF gpio_general_tri_iobuf_3
       (.I(gpio_general_tri_o_3),
        .IO(gpio_general_tri_io[3]),
        .O(gpio_general_tri_i_3),
        .T(gpio_general_tri_t_3));
  IOBUF iic_scl_iobuf
       (.I(iic_scl_o),
        .IO(iic_scl_io),
        .O(iic_scl_i),
        .T(iic_scl_t));
  IOBUF iic_sda_iobuf
       (.I(iic_sda_o),
        .IO(iic_sda_io),
        .O(iic_sda_i),
        .T(iic_sda_t));
  mb_subsystem mb_subsystem_i
       (.DDR3_addr(DDR3_addr),
        .DDR3_ba(DDR3_ba),
        .DDR3_cas_n(DDR3_cas_n),
        .DDR3_ck_n(DDR3_ck_n),
        .DDR3_ck_p(DDR3_ck_p),
        .DDR3_cke(DDR3_cke),
        .DDR3_cs_n(DDR3_cs_n),
        .DDR3_dm(DDR3_dm),
        .DDR3_dq(DDR3_dq),
        .DDR3_dqs_n(DDR3_dqs_n),
        .DDR3_dqs_p(DDR3_dqs_p),
        .DDR3_odt(DDR3_odt),
        .DDR3_ras_n(DDR3_ras_n),
        .DDR3_reset_n(DDR3_reset_n),
        .DDR3_we_n(DDR3_we_n),
        .clk_50MHz(clk_50MHz),
        .gpio_fx2_fifo_tri_i({gpio_fx2_fifo_tri_i_4,gpio_fx2_fifo_tri_i_3,gpio_fx2_fifo_tri_i_2,gpio_fx2_fifo_tri_i_1,gpio_fx2_fifo_tri_i_0}),
        .gpio_fx2_fifo_tri_o({gpio_fx2_fifo_tri_o_4,gpio_fx2_fifo_tri_o_3,gpio_fx2_fifo_tri_o_2,gpio_fx2_fifo_tri_o_1,gpio_fx2_fifo_tri_o_0}),
        .gpio_fx2_fifo_tri_t({gpio_fx2_fifo_tri_t_4,gpio_fx2_fifo_tri_t_3,gpio_fx2_fifo_tri_t_2,gpio_fx2_fifo_tri_t_1,gpio_fx2_fifo_tri_t_0}),
        .gpio_general_tri_i({gpio_general_tri_i_3,gpio_general_tri_i_2,gpio_general_tri_i_1,gpio_general_tri_i_0}),
        .gpio_general_tri_o({gpio_general_tri_o_3,gpio_general_tri_o_2,gpio_general_tri_o_1,gpio_general_tri_o_0}),
        .gpio_general_tri_t({gpio_general_tri_t_3,gpio_general_tri_t_2,gpio_general_tri_t_1,gpio_general_tri_t_0}),
        .gpio_key_tri_i(gpio_key_tri_i),
        .gpio_led_tri_o(gpio_led_tri_o),
        .i_adc_data(i_adc_data),
        .i_slave_fifo_empty_n(i_slave_fifo_empty_n),
        .i_slave_fifo_full_n(i_slave_fifo_full_n),
        .iic_scl_i(iic_scl_i),
        .iic_scl_o(iic_scl_o),
        .iic_scl_t(iic_scl_t),
        .iic_sda_i(iic_sda_i),
        .iic_sda_o(iic_sda_o),
        .iic_sda_t(iic_sda_t),
        .o_adcclk(o_adcclk),
        .o_cdsclk1(o_cdsclk1),
        .o_cdsclk2(o_cdsclk2),
        .o_p1h(o_p1h),
        .o_p1v(o_p1v),
        .o_p2h(o_p2h),
        .o_p2v_tg(o_p2v_tg),
        .o_p3h(o_p3h),
        .o_p4h_sg(o_p4h_sg),
        .o_rg(o_rg),
        .o_slave_fifo_clk(o_slave_fifo_clk),
        .o_slave_fifo_data(o_slave_fifo_data),
        .o_slave_fifo_data_last_n(o_slave_fifo_data_last_n),
        .o_slave_fifo_data_wr_en_n(o_slave_fifo_data_wr_en_n),
        .reset(reset),
        .spi_io0_i(spi_io0_i),
        .spi_io0_o(spi_io0_o),
        .spi_io0_t(spi_io0_t),
        .spi_io1_i(spi_io1_i),
        .spi_io1_o(spi_io1_o),
        .spi_io1_t(spi_io1_t),
        .spi_sck_i(spi_sck_i),
        .spi_sck_o(spi_sck_o),
        .spi_sck_t(spi_sck_t),
        .spi_ss_i({spi_ss_i_2,spi_ss_i_1,spi_ss_i_0}),
        .spi_ss_o({spi_ss_o_2,spi_ss_o_1,spi_ss_o_0}),
        .spi_ss_t(spi_ss_t),
        .uart_rxd(uart_rxd),
        .uart_txd(uart_txd));
  IOBUF spi_io0_iobuf
       (.I(spi_io0_o),
        .IO(spi_io0_io),
        .O(spi_io0_i),
        .T(spi_io0_t));
  IOBUF spi_io1_iobuf
       (.I(spi_io1_o),
        .IO(spi_io1_io),
        .O(spi_io1_i),
        .T(spi_io1_t));
  IOBUF spi_sck_iobuf
       (.I(spi_sck_o),
        .IO(spi_sck_io),
        .O(spi_sck_i),
        .T(spi_sck_t));
  IOBUF spi_ss_iobuf_0
       (.I(spi_ss_o_0),
        .IO(spi_ss_io[0]),
        .O(spi_ss_i_0),
        .T(spi_ss_t));
  IOBUF spi_ss_iobuf_1
       (.I(spi_ss_o_1),
        .IO(spi_ss_io[1]),
        .O(spi_ss_i_1),
        .T(spi_ss_t));
  IOBUF spi_ss_iobuf_2
       (.I(spi_ss_o_2),
        .IO(spi_ss_io[2]),
        .O(spi_ss_i_2),
        .T(spi_ss_t));
endmodule

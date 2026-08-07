// Copyright 1986-2020 Xilinx, Inc. All Rights Reserved.
// --------------------------------------------------------------------------------
// Tool Version: Vivado v.2020.1 (win64) Build 2902540 Wed May 27 19:54:49 MDT 2020
// Date        : Fri Aug  7 17:34:58 2026
// Host        : DESKTOP-KD2H86C running 64-bit major release  (build 9200)
// Command     : write_verilog -force -mode synth_stub
//               d:/2607-Pro-S16011-CCD/02-fpga/ccd_controller_hardware/vivado_proj/ccd_controller_hardware.srcs/sources_1/bd/mb_subsystem/ip/mb_subsystem_ccd_controller_v1_0_0_0/mb_subsystem_ccd_controller_v1_0_0_0_stub.v
// Design      : mb_subsystem_ccd_controller_v1_0_0_0
// Purpose     : Stub declaration of top-level module interface
// Device      : xc7a100tfgg484-2
// --------------------------------------------------------------------------------

// This empty module with port declaration file causes synthesis tools to infer a black box for IP.
// The synthesis directives are for Synopsys Synplify support to prevent IO buffer insertion.
// Please paste the declaration into a Verilog source file or add the file as an additional source.
(* X_CORE_INFO = "ccd_controller_v1_0,Vivado 2020.1" *)
module mb_subsystem_ccd_controller_v1_0_0_0(intr, o_adcclk, o_p1v, o_p2v_tg, o_p1h, o_p2h, o_p3h, 
  o_p4h_sg, o_rg, o_cdsclk1, o_cdsclk2, i_adc_data, i_rd_clk, i_rd_clk_n, i_slave_fifo_empty_n, 
  i_slave_fifo_full_n, o_slave_fifo_data, o_slave_fifo_data_wr_en_n, 
  o_slave_fifo_data_last_n, o_slave_fifo_clk, i_ui_clk, i_mmcm_locked, 
  i_init_calib_complete, M_AXI_AWID, M_AXI_AWADDR, M_AXI_AWLEN, M_AXI_AWSIZE, M_AXI_AWBURST, 
  M_AXI_AWLOCK, M_AXI_AWCACHE, M_AXI_AWPROT, M_AXI_AWQOS, M_AXI_AWREGION, M_AXI_AWVALID, 
  M_AXI_AWREADY, M_AXI_WDATA, M_AXI_WSTRB, M_AXI_WLAST, M_AXI_WVALID, M_AXI_WREADY, M_AXI_BID, 
  M_AXI_BRESP, M_AXI_BVALID, M_AXI_BREADY, M_AXI_ARID, M_AXI_ARADDR, M_AXI_ARLEN, M_AXI_ARSIZE, 
  M_AXI_ARBURST, M_AXI_ARLOCK, M_AXI_ARCACHE, M_AXI_ARPROT, M_AXI_ARQOS, M_AXI_ARREGION, 
  M_AXI_ARVALID, M_AXI_ARREADY, M_AXI_RID, M_AXI_RDATA, M_AXI_RRESP, M_AXI_RLAST, M_AXI_RVALID, 
  M_AXI_RREADY, s00_axi_aclk, s00_axi_aresetn, s00_axi_awaddr, s00_axi_awprot, 
  s00_axi_awvalid, s00_axi_awready, s00_axi_wdata, s00_axi_wstrb, s00_axi_wvalid, 
  s00_axi_wready, s00_axi_bresp, s00_axi_bvalid, s00_axi_bready, s00_axi_araddr, 
  s00_axi_arprot, s00_axi_arvalid, s00_axi_arready, s00_axi_rdata, s00_axi_rresp, 
  s00_axi_rvalid, s00_axi_rready)
/* synthesis syn_black_box black_box_pad_pin="intr,o_adcclk,o_p1v,o_p2v_tg,o_p1h,o_p2h,o_p3h,o_p4h_sg,o_rg,o_cdsclk1,o_cdsclk2,i_adc_data[7:0],i_rd_clk,i_rd_clk_n,i_slave_fifo_empty_n,i_slave_fifo_full_n,o_slave_fifo_data[15:0],o_slave_fifo_data_wr_en_n,o_slave_fifo_data_last_n,o_slave_fifo_clk,i_ui_clk,i_mmcm_locked,i_init_calib_complete,M_AXI_AWID[3:0],M_AXI_AWADDR[29:0],M_AXI_AWLEN[7:0],M_AXI_AWSIZE[2:0],M_AXI_AWBURST[1:0],M_AXI_AWLOCK,M_AXI_AWCACHE[3:0],M_AXI_AWPROT[2:0],M_AXI_AWQOS[3:0],M_AXI_AWREGION[3:0],M_AXI_AWVALID,M_AXI_AWREADY,M_AXI_WDATA[127:0],M_AXI_WSTRB[15:0],M_AXI_WLAST,M_AXI_WVALID,M_AXI_WREADY,M_AXI_BID[3:0],M_AXI_BRESP[1:0],M_AXI_BVALID,M_AXI_BREADY,M_AXI_ARID[3:0],M_AXI_ARADDR[29:0],M_AXI_ARLEN[7:0],M_AXI_ARSIZE[2:0],M_AXI_ARBURST[1:0],M_AXI_ARLOCK,M_AXI_ARCACHE[3:0],M_AXI_ARPROT[2:0],M_AXI_ARQOS[3:0],M_AXI_ARREGION[3:0],M_AXI_ARVALID,M_AXI_ARREADY,M_AXI_RID[3:0],M_AXI_RDATA[127:0],M_AXI_RRESP[1:0],M_AXI_RLAST,M_AXI_RVALID,M_AXI_RREADY,s00_axi_aclk,s00_axi_aresetn,s00_axi_awaddr[5:0],s00_axi_awprot[2:0],s00_axi_awvalid,s00_axi_awready,s00_axi_wdata[31:0],s00_axi_wstrb[3:0],s00_axi_wvalid,s00_axi_wready,s00_axi_bresp[1:0],s00_axi_bvalid,s00_axi_bready,s00_axi_araddr[5:0],s00_axi_arprot[2:0],s00_axi_arvalid,s00_axi_arready,s00_axi_rdata[31:0],s00_axi_rresp[1:0],s00_axi_rvalid,s00_axi_rready" */;
  output intr;
  output o_adcclk;
  output o_p1v;
  output o_p2v_tg;
  output o_p1h;
  output o_p2h;
  output o_p3h;
  output o_p4h_sg;
  output o_rg;
  output o_cdsclk1;
  output o_cdsclk2;
  input [7:0]i_adc_data;
  input i_rd_clk;
  input i_rd_clk_n;
  input i_slave_fifo_empty_n;
  input i_slave_fifo_full_n;
  output [15:0]o_slave_fifo_data;
  output o_slave_fifo_data_wr_en_n;
  output o_slave_fifo_data_last_n;
  output o_slave_fifo_clk;
  input i_ui_clk;
  input i_mmcm_locked;
  input i_init_calib_complete;
  output [3:0]M_AXI_AWID;
  output [29:0]M_AXI_AWADDR;
  output [7:0]M_AXI_AWLEN;
  output [2:0]M_AXI_AWSIZE;
  output [1:0]M_AXI_AWBURST;
  output M_AXI_AWLOCK;
  output [3:0]M_AXI_AWCACHE;
  output [2:0]M_AXI_AWPROT;
  output [3:0]M_AXI_AWQOS;
  output [3:0]M_AXI_AWREGION;
  output M_AXI_AWVALID;
  input M_AXI_AWREADY;
  output [127:0]M_AXI_WDATA;
  output [15:0]M_AXI_WSTRB;
  output M_AXI_WLAST;
  output M_AXI_WVALID;
  input M_AXI_WREADY;
  input [3:0]M_AXI_BID;
  input [1:0]M_AXI_BRESP;
  input M_AXI_BVALID;
  output M_AXI_BREADY;
  output [3:0]M_AXI_ARID;
  output [29:0]M_AXI_ARADDR;
  output [7:0]M_AXI_ARLEN;
  output [2:0]M_AXI_ARSIZE;
  output [1:0]M_AXI_ARBURST;
  output M_AXI_ARLOCK;
  output [3:0]M_AXI_ARCACHE;
  output [2:0]M_AXI_ARPROT;
  output [3:0]M_AXI_ARQOS;
  output [3:0]M_AXI_ARREGION;
  output M_AXI_ARVALID;
  input M_AXI_ARREADY;
  input [3:0]M_AXI_RID;
  input [127:0]M_AXI_RDATA;
  input [1:0]M_AXI_RRESP;
  input M_AXI_RLAST;
  input M_AXI_RVALID;
  output M_AXI_RREADY;
  input s00_axi_aclk;
  input s00_axi_aresetn;
  input [5:0]s00_axi_awaddr;
  input [2:0]s00_axi_awprot;
  input s00_axi_awvalid;
  output s00_axi_awready;
  input [31:0]s00_axi_wdata;
  input [3:0]s00_axi_wstrb;
  input s00_axi_wvalid;
  output s00_axi_wready;
  output [1:0]s00_axi_bresp;
  output s00_axi_bvalid;
  input s00_axi_bready;
  input [5:0]s00_axi_araddr;
  input [2:0]s00_axi_arprot;
  input s00_axi_arvalid;
  output s00_axi_arready;
  output [31:0]s00_axi_rdata;
  output [1:0]s00_axi_rresp;
  output s00_axi_rvalid;
  input s00_axi_rready;
endmodule

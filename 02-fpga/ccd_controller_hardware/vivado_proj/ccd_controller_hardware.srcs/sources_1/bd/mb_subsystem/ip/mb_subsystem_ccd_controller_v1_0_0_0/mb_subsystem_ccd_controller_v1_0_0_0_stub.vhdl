-- Copyright 1986-2020 Xilinx, Inc. All Rights Reserved.
-- --------------------------------------------------------------------------------
-- Tool Version: Vivado v.2020.1 (win64) Build 2902540 Wed May 27 19:54:49 MDT 2020
-- Date        : Sat Aug  8 14:43:55 2026
-- Host        : DESKTOP-KD2H86C running 64-bit major release  (build 9200)
-- Command     : write_vhdl -force -mode synth_stub
--               d:/2607-Pro-S16011-CCD/02-fpga/ccd_controller_hardware/vivado_proj/ccd_controller_hardware.srcs/sources_1/bd/mb_subsystem/ip/mb_subsystem_ccd_controller_v1_0_0_0/mb_subsystem_ccd_controller_v1_0_0_0_stub.vhdl
-- Design      : mb_subsystem_ccd_controller_v1_0_0_0
-- Purpose     : Stub declaration of top-level module interface
-- Device      : xc7a100tfgg484-2
-- --------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity mb_subsystem_ccd_controller_v1_0_0_0 is
  Port ( 
    intr : out STD_LOGIC;
    o_adcclk : out STD_LOGIC;
    o_p1v : out STD_LOGIC;
    o_p2v_tg : out STD_LOGIC;
    o_p1h : out STD_LOGIC;
    o_p2h : out STD_LOGIC;
    o_p3h : out STD_LOGIC;
    o_p4h_sg : out STD_LOGIC;
    o_rg : out STD_LOGIC;
    o_cdsclk1 : out STD_LOGIC;
    o_cdsclk2 : out STD_LOGIC;
    i_adc_data : in STD_LOGIC_VECTOR ( 7 downto 0 );
    i_rd_clk : in STD_LOGIC;
    i_rd_clk_n : in STD_LOGIC;
    i_slave_fifo_empty_n : in STD_LOGIC;
    i_slave_fifo_full_n : in STD_LOGIC;
    o_slave_fifo_data : out STD_LOGIC_VECTOR ( 15 downto 0 );
    o_slave_fifo_data_wr_en_n : out STD_LOGIC;
    o_slave_fifo_data_last_n : out STD_LOGIC;
    o_slave_fifo_clk : out STD_LOGIC;
    i_ui_clk : in STD_LOGIC;
    i_mmcm_locked : in STD_LOGIC;
    i_init_calib_complete : in STD_LOGIC;
    M_AXI_AWID : out STD_LOGIC_VECTOR ( 3 downto 0 );
    M_AXI_AWADDR : out STD_LOGIC_VECTOR ( 29 downto 0 );
    M_AXI_AWLEN : out STD_LOGIC_VECTOR ( 7 downto 0 );
    M_AXI_AWSIZE : out STD_LOGIC_VECTOR ( 2 downto 0 );
    M_AXI_AWBURST : out STD_LOGIC_VECTOR ( 1 downto 0 );
    M_AXI_AWLOCK : out STD_LOGIC;
    M_AXI_AWCACHE : out STD_LOGIC_VECTOR ( 3 downto 0 );
    M_AXI_AWPROT : out STD_LOGIC_VECTOR ( 2 downto 0 );
    M_AXI_AWQOS : out STD_LOGIC_VECTOR ( 3 downto 0 );
    M_AXI_AWREGION : out STD_LOGIC_VECTOR ( 3 downto 0 );
    M_AXI_AWVALID : out STD_LOGIC;
    M_AXI_AWREADY : in STD_LOGIC;
    M_AXI_WDATA : out STD_LOGIC_VECTOR ( 127 downto 0 );
    M_AXI_WSTRB : out STD_LOGIC_VECTOR ( 15 downto 0 );
    M_AXI_WLAST : out STD_LOGIC;
    M_AXI_WVALID : out STD_LOGIC;
    M_AXI_WREADY : in STD_LOGIC;
    M_AXI_BID : in STD_LOGIC_VECTOR ( 3 downto 0 );
    M_AXI_BRESP : in STD_LOGIC_VECTOR ( 1 downto 0 );
    M_AXI_BVALID : in STD_LOGIC;
    M_AXI_BREADY : out STD_LOGIC;
    M_AXI_ARID : out STD_LOGIC_VECTOR ( 3 downto 0 );
    M_AXI_ARADDR : out STD_LOGIC_VECTOR ( 29 downto 0 );
    M_AXI_ARLEN : out STD_LOGIC_VECTOR ( 7 downto 0 );
    M_AXI_ARSIZE : out STD_LOGIC_VECTOR ( 2 downto 0 );
    M_AXI_ARBURST : out STD_LOGIC_VECTOR ( 1 downto 0 );
    M_AXI_ARLOCK : out STD_LOGIC;
    M_AXI_ARCACHE : out STD_LOGIC_VECTOR ( 3 downto 0 );
    M_AXI_ARPROT : out STD_LOGIC_VECTOR ( 2 downto 0 );
    M_AXI_ARQOS : out STD_LOGIC_VECTOR ( 3 downto 0 );
    M_AXI_ARREGION : out STD_LOGIC_VECTOR ( 3 downto 0 );
    M_AXI_ARVALID : out STD_LOGIC;
    M_AXI_ARREADY : in STD_LOGIC;
    M_AXI_RID : in STD_LOGIC_VECTOR ( 3 downto 0 );
    M_AXI_RDATA : in STD_LOGIC_VECTOR ( 127 downto 0 );
    M_AXI_RRESP : in STD_LOGIC_VECTOR ( 1 downto 0 );
    M_AXI_RLAST : in STD_LOGIC;
    M_AXI_RVALID : in STD_LOGIC;
    M_AXI_RREADY : out STD_LOGIC;
    s00_axi_aclk : in STD_LOGIC;
    s00_axi_aresetn : in STD_LOGIC;
    s00_axi_awaddr : in STD_LOGIC_VECTOR ( 5 downto 0 );
    s00_axi_awprot : in STD_LOGIC_VECTOR ( 2 downto 0 );
    s00_axi_awvalid : in STD_LOGIC;
    s00_axi_awready : out STD_LOGIC;
    s00_axi_wdata : in STD_LOGIC_VECTOR ( 31 downto 0 );
    s00_axi_wstrb : in STD_LOGIC_VECTOR ( 3 downto 0 );
    s00_axi_wvalid : in STD_LOGIC;
    s00_axi_wready : out STD_LOGIC;
    s00_axi_bresp : out STD_LOGIC_VECTOR ( 1 downto 0 );
    s00_axi_bvalid : out STD_LOGIC;
    s00_axi_bready : in STD_LOGIC;
    s00_axi_araddr : in STD_LOGIC_VECTOR ( 5 downto 0 );
    s00_axi_arprot : in STD_LOGIC_VECTOR ( 2 downto 0 );
    s00_axi_arvalid : in STD_LOGIC;
    s00_axi_arready : out STD_LOGIC;
    s00_axi_rdata : out STD_LOGIC_VECTOR ( 31 downto 0 );
    s00_axi_rresp : out STD_LOGIC_VECTOR ( 1 downto 0 );
    s00_axi_rvalid : out STD_LOGIC;
    s00_axi_rready : in STD_LOGIC
  );

end mb_subsystem_ccd_controller_v1_0_0_0;

architecture stub of mb_subsystem_ccd_controller_v1_0_0_0 is
attribute syn_black_box : boolean;
attribute black_box_pad_pin : string;
attribute syn_black_box of stub : architecture is true;
attribute black_box_pad_pin of stub : architecture is "intr,o_adcclk,o_p1v,o_p2v_tg,o_p1h,o_p2h,o_p3h,o_p4h_sg,o_rg,o_cdsclk1,o_cdsclk2,i_adc_data[7:0],i_rd_clk,i_rd_clk_n,i_slave_fifo_empty_n,i_slave_fifo_full_n,o_slave_fifo_data[15:0],o_slave_fifo_data_wr_en_n,o_slave_fifo_data_last_n,o_slave_fifo_clk,i_ui_clk,i_mmcm_locked,i_init_calib_complete,M_AXI_AWID[3:0],M_AXI_AWADDR[29:0],M_AXI_AWLEN[7:0],M_AXI_AWSIZE[2:0],M_AXI_AWBURST[1:0],M_AXI_AWLOCK,M_AXI_AWCACHE[3:0],M_AXI_AWPROT[2:0],M_AXI_AWQOS[3:0],M_AXI_AWREGION[3:0],M_AXI_AWVALID,M_AXI_AWREADY,M_AXI_WDATA[127:0],M_AXI_WSTRB[15:0],M_AXI_WLAST,M_AXI_WVALID,M_AXI_WREADY,M_AXI_BID[3:0],M_AXI_BRESP[1:0],M_AXI_BVALID,M_AXI_BREADY,M_AXI_ARID[3:0],M_AXI_ARADDR[29:0],M_AXI_ARLEN[7:0],M_AXI_ARSIZE[2:0],M_AXI_ARBURST[1:0],M_AXI_ARLOCK,M_AXI_ARCACHE[3:0],M_AXI_ARPROT[2:0],M_AXI_ARQOS[3:0],M_AXI_ARREGION[3:0],M_AXI_ARVALID,M_AXI_ARREADY,M_AXI_RID[3:0],M_AXI_RDATA[127:0],M_AXI_RRESP[1:0],M_AXI_RLAST,M_AXI_RVALID,M_AXI_RREADY,s00_axi_aclk,s00_axi_aresetn,s00_axi_awaddr[5:0],s00_axi_awprot[2:0],s00_axi_awvalid,s00_axi_awready,s00_axi_wdata[31:0],s00_axi_wstrb[3:0],s00_axi_wvalid,s00_axi_wready,s00_axi_bresp[1:0],s00_axi_bvalid,s00_axi_bready,s00_axi_araddr[5:0],s00_axi_arprot[2:0],s00_axi_arvalid,s00_axi_arready,s00_axi_rdata[31:0],s00_axi_rresp[1:0],s00_axi_rvalid,s00_axi_rready";
attribute X_CORE_INFO : string;
attribute X_CORE_INFO of stub : architecture is "ccd_controller_v1_0,Vivado 2020.1";
begin
end;

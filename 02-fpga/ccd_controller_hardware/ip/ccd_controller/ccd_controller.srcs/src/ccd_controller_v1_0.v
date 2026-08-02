
`timescale 1 ns / 1 ps

	module ccd_controller_v1_0 #
	(
		// Users to add parameters here
		parameter integer MAX_FRAME_DEPTH = 131072,
		parameter integer MAX_FRAMES      = 8,
		// User parameters ends
		// Do not modify the parameters beyond this line


		// Parameters of Axi Slave Bus Interface S00_AXI
		parameter integer C_S00_AXI_DATA_WIDTH	= 32,
		parameter integer C_S00_AXI_ADDR_WIDTH	= 6
	)
	(
		// Users to add ports here

		// 中断
		output wire         intr,

		// CCD 驱动信号
		output wire         o_adcclk,
		output wire         o_p1v,
		output wire         o_p2v_tg,
		output wire         o_p1h,
		output wire         o_p2h,
		output wire         o_p3h,
		output wire         o_p4h_sg,
		output wire         o_rg,
		output wire         o_cdsclk1,
		output wire         o_cdsclk2,

		// ADC 数据
		input  wire [7:0]   i_adc_data,

		// FX2 Slave FIFO
		input  wire         i_rd_clk,
		input  wire         i_rd_clk_n,
		input  wire         i_slave_fifo_empty_n,
		input  wire         i_slave_fifo_full_n,
		output wire [15:0]  o_slave_fifo_data,
		output wire         o_slave_fifo_data_valid_n,
		output wire         o_slave_fifo_clk,

		// MIG / DDR3
		input  wire         i_ui_clk,
		input  wire         i_mmcm_locked,
		input  wire         i_init_calib_complete,

		// AXI4 Master → MIG S_AXI
		output wire [3:0]   M_AXI_AWID,
		output wire [29:0]  M_AXI_AWADDR,
		output wire [7:0]   M_AXI_AWLEN,
		output wire [2:0]   M_AXI_AWSIZE,
		output wire [1:0]   M_AXI_AWBURST,
		output wire         M_AXI_AWLOCK,
		output wire [3:0]   M_AXI_AWCACHE,
		output wire [2:0]   M_AXI_AWPROT,
		output wire [3:0]   M_AXI_AWQOS,
		output wire [3:0]   M_AXI_AWREGION,
		output wire         M_AXI_AWVALID,
		input  wire         M_AXI_AWREADY,
		output wire [127:0] M_AXI_WDATA,
		output wire [15:0]  M_AXI_WSTRB,
		output wire         M_AXI_WLAST,
		output wire         M_AXI_WVALID,
		input  wire         M_AXI_WREADY,
		input  wire [3:0]   M_AXI_BID,
		input  wire [1:0]   M_AXI_BRESP,
		input  wire         M_AXI_BVALID,
		output wire         M_AXI_BREADY,
		output wire [3:0]   M_AXI_ARID,
		output wire [29:0]  M_AXI_ARADDR,
		output wire [7:0]   M_AXI_ARLEN,
		output wire [2:0]   M_AXI_ARSIZE,
		output wire [1:0]   M_AXI_ARBURST,
		output wire         M_AXI_ARLOCK,
		output wire [3:0]   M_AXI_ARCACHE,
		output wire [2:0]   M_AXI_ARPROT,
		output wire [3:0]   M_AXI_ARQOS,
		output wire [3:0]   M_AXI_ARREGION,
		output wire         M_AXI_ARVALID,
		input  wire         M_AXI_ARREADY,
		input  wire [3:0]   M_AXI_RID,
		input  wire [127:0] M_AXI_RDATA,
		input  wire [1:0]   M_AXI_RRESP,
		input  wire         M_AXI_RLAST,
		input  wire         M_AXI_RVALID,
		output wire         M_AXI_RREADY,
		// User ports ends
		// Do not modify the ports beyond this line


		// Ports of Axi Slave Bus Interface S00_AXI
		input wire  s00_axi_aclk,
		input wire  s00_axi_aresetn,
		input wire [C_S00_AXI_ADDR_WIDTH-1 : 0] s00_axi_awaddr,
		input wire [2 : 0] s00_axi_awprot,
		input wire  s00_axi_awvalid,
		output wire  s00_axi_awready,
		input wire [C_S00_AXI_DATA_WIDTH-1 : 0] s00_axi_wdata,
		input wire [(C_S00_AXI_DATA_WIDTH/8)-1 : 0] s00_axi_wstrb,
		input wire  s00_axi_wvalid,
		output wire  s00_axi_wready,
		output wire [1 : 0] s00_axi_bresp,
		output wire  s00_axi_bvalid,
		input wire  s00_axi_bready,
		input wire [C_S00_AXI_ADDR_WIDTH-1 : 0] s00_axi_araddr,
		input wire [2 : 0] s00_axi_arprot,
		input wire  s00_axi_arvalid,
		output wire  s00_axi_arready,
		output wire [C_S00_AXI_DATA_WIDTH-1 : 0] s00_axi_rdata,
		output wire [1 : 0] s00_axi_rresp,
		output wire  s00_axi_rvalid,
		input wire  s00_axi_rready
	);
// Instantiation of Axi Bus Interface S00_AXI
	ccd_controller_v1_0_S00_AXI # ( 
		.C_S_AXI_DATA_WIDTH(C_S00_AXI_DATA_WIDTH),
		.C_S_AXI_ADDR_WIDTH(C_S00_AXI_ADDR_WIDTH),
		.MAX_FRAME_DEPTH(MAX_FRAME_DEPTH),
		.MAX_FRAMES     (MAX_FRAMES)
	) ccd_controller_v1_0_S00_AXI_inst (
		.S_AXI_ACLK(s00_axi_aclk),
		.S_AXI_ARESETN(s00_axi_aresetn),
		.S_AXI_AWADDR(s00_axi_awaddr),
		.S_AXI_AWPROT(s00_axi_awprot),
		.S_AXI_AWVALID(s00_axi_awvalid),
		.S_AXI_AWREADY(s00_axi_awready),
		.S_AXI_WDATA(s00_axi_wdata),
		.S_AXI_WSTRB(s00_axi_wstrb),
		.S_AXI_WVALID(s00_axi_wvalid),
		.S_AXI_WREADY(s00_axi_wready),
		.S_AXI_BRESP(s00_axi_bresp),
		.S_AXI_BVALID(s00_axi_bvalid),
		.S_AXI_BREADY(s00_axi_bready),
		.S_AXI_ARADDR(s00_axi_araddr),
		.S_AXI_ARPROT(s00_axi_arprot),
		.S_AXI_ARVALID(s00_axi_arvalid),
		.S_AXI_ARREADY(s00_axi_arready),
		.S_AXI_RDATA(s00_axi_rdata),
		.S_AXI_RRESP(s00_axi_rresp),
		.S_AXI_RVALID(s00_axi_rvalid),
		.S_AXI_RREADY(s00_axi_rready),
		// 用户端口
		.intr            (intr),
		.o_adcclk        (o_adcclk),
		.o_p1v           (o_p1v),
		.o_p2v_tg        (o_p2v_tg),
		.o_p1h           (o_p1h),
		.o_p2h           (o_p2h),
		.o_p3h           (o_p3h),
		.o_p4h_sg        (o_p4h_sg),
		.o_rg            (o_rg),
		.o_cdsclk1       (o_cdsclk1),
		.o_cdsclk2       (o_cdsclk2),
		.i_adc_data      (i_adc_data),
		.i_rd_clk        (i_rd_clk),
		.i_rd_clk_n      (i_rd_clk_n),
		.o_slave_fifo_clk(o_slave_fifo_clk),
		.i_slave_fifo_empty_n(i_slave_fifo_empty_n),
		.i_slave_fifo_full_n (i_slave_fifo_full_n),
		.o_slave_fifo_data    (o_slave_fifo_data),
		.o_slave_fifo_data_valid_n(o_slave_fifo_data_valid_n),
		.i_ui_clk        (i_ui_clk),
		.i_mmcm_locked    (i_mmcm_locked),
		.i_init_calib_complete(i_init_calib_complete),
		.M_AXI_AWID      (M_AXI_AWID),
		.M_AXI_AWADDR    (M_AXI_AWADDR),
		.M_AXI_AWLEN     (M_AXI_AWLEN),
		.M_AXI_AWSIZE    (M_AXI_AWSIZE),
		.M_AXI_AWBURST   (M_AXI_AWBURST),
		.M_AXI_AWLOCK    (M_AXI_AWLOCK),
		.M_AXI_AWCACHE   (M_AXI_AWCACHE),
		.M_AXI_AWPROT    (M_AXI_AWPROT),
		.M_AXI_AWQOS     (M_AXI_AWQOS),
		.M_AXI_AWREGION  (M_AXI_AWREGION),
		.M_AXI_AWVALID   (M_AXI_AWVALID),
		.M_AXI_AWREADY   (M_AXI_AWREADY),
		.M_AXI_WDATA     (M_AXI_WDATA),
		.M_AXI_WSTRB     (M_AXI_WSTRB),
		.M_AXI_WLAST     (M_AXI_WLAST),
		.M_AXI_WVALID    (M_AXI_WVALID),
		.M_AXI_WREADY    (M_AXI_WREADY),
		.M_AXI_BID       (M_AXI_BID),
		.M_AXI_BRESP     (M_AXI_BRESP),
		.M_AXI_BVALID    (M_AXI_BVALID),
		.M_AXI_BREADY    (M_AXI_BREADY),
		.M_AXI_ARID      (M_AXI_ARID),
		.M_AXI_ARADDR    (M_AXI_ARADDR),
		.M_AXI_ARLEN     (M_AXI_ARLEN),
		.M_AXI_ARSIZE    (M_AXI_ARSIZE),
		.M_AXI_ARBURST   (M_AXI_ARBURST),
		.M_AXI_ARLOCK    (M_AXI_ARLOCK),
		.M_AXI_ARCACHE   (M_AXI_ARCACHE),
		.M_AXI_ARPROT    (M_AXI_ARPROT),
		.M_AXI_ARQOS     (M_AXI_ARQOS),
		.M_AXI_ARREGION  (M_AXI_ARREGION),
		.M_AXI_ARVALID   (M_AXI_ARVALID),
		.M_AXI_ARREADY   (M_AXI_ARREADY),
		.M_AXI_RID       (M_AXI_RID),
		.M_AXI_RDATA     (M_AXI_RDATA),
		.M_AXI_RRESP     (M_AXI_RRESP),
		.M_AXI_RLAST     (M_AXI_RLAST),
		.M_AXI_RVALID    (M_AXI_RVALID),
		.M_AXI_RREADY    (M_AXI_RREADY)
	);

	// Add user logic here
	// User logic ends

	endmodule

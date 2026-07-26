`timescale 1ns / 1ps
//==============================================================================
// Module : ccd_frame_buf_ddr
// Desc   : DDR 帧缓存顶层模块（薄封装）。
//          内部架构:
//            ccd_frame_buf_ddr_ctrl: 所有控制逻辑 + wr/rd FIFO + AXI adapter
//            mig_7series_0: MIG DDR3 Controller
//
//          需要 Vivado 创建以下 IP:
//            wr_ddr3_fifo: FIFO Generator, 异步, 16bit×512(实511) 到 128bit×64(实63)
//            rd_ddr3_fifo: FIFO Generator, 异步, 128bit×64(实63) 到 16bit×512(实511)
//            mig_7series_0: MIG DDR3 Controller with axi interface
//          注: wr/rd FIFO 在 ccd_frame_buf_ddr_ctrl 内部例化。
//==============================================================================
module ccd_frame_buf_ddr #(
    parameter MAX_FRAME_DEPTH = 131072,  // 每帧最大像素数 (每个像素 2 字节)
    parameter MAX_FRAMES      = 8        // 最大缓存帧数
) (
    // ---- 写侧 (ADCCLK 域) ----
    input  wire         i_adcclk,
    input  wire         i_rst_n,
    input  wire [15:0]  i_wr_data,
    input  wire         i_wr_en,
    input  wire [1:0]   i_pixel_type,
    input  wire         i_frame_start,
    input  wire         i_frame_end,
    input  wire [15:0]  i_image_width,
    input  wire [15:0]  i_image_height,
    input  wire [1:0]   i_read_mode,

    // ---- 读侧 (FX2 域: i_rd_clk) ----
    input  wire         i_rd_clk,
    output wire [15:0]  o_fifo_data,
    output wire [$clog2(MAX_FRAMES+1)-1:0] o_frame_num,
    input  wire         i_fifo_rd_en,
    output wire         o_fifo_last_word,

    // ---- 异常 ----
    output wire         o_frame_exception,

    // ---- DDR3 时钟与复位 ----
    input  wire         i_ddr3_clk100m,
    input  wire         i_ddr3_clk200m_ref,
    input  wire         i_mig_rst_n,        // MIG 专用复位 (低有效), 独立于 i_rst_n
    output wire         o_ddr3_init_done,

    // ---- DDR3 物理接口 ----
    inout  [31:0]       ddr3_dq,
    inout  [3:0]        ddr3_dqs_n,
    inout  [3:0]        ddr3_dqs_p,
    output [14:0]       ddr3_addr,
    output [2:0]        ddr3_ba,
    output              ddr3_ras_n,
    output              ddr3_cas_n,
    output              ddr3_we_n,
    output              ddr3_reset_n,
    output [0:0]        ddr3_ck_p,
    output [0:0]        ddr3_ck_n,
    output [0:0]        ddr3_cke,
    output [0:0]        ddr3_cs_n,
    output [3:0]        ddr3_dm,
    output [0:0]        ddr3_odt
);

    // ==================================================================
    // 本地参数
    // ==================================================================
    localparam AXI_ADDR_WIDTH = 30;
    localparam AXI_BURST_LEN  = 8'd31;
    localparam FIFO_ADDR_WIDTH = 6;

    // ==================================================================
    // MIG 信号
    // ==================================================================
    wire ui_clk;
    wire ui_clk_sync_rst;
    wire init_calib_complete;
    wire mmcm_locked;
    wire ddr3_init_done_w;

    assign ddr3_init_done_w = mmcm_locked && init_calib_complete;
    assign o_ddr3_init_done = ddr3_init_done_w;

    // 控制器复位: 系统复位 AND DDR3 初始化完成
    reg ctrl_rst_n;
    always @(posedge ui_clk)
        ctrl_rst_n <= i_rst_n && ddr3_init_done_w;

    // ==================================================================
    // Controller ↔ MIG AXI4 互连
    // ==================================================================
    // 写地址
    wire [3:0]   s_axi_awid;
    wire [29:0]  s_axi_awaddr;
    wire [7:0]   s_axi_awlen;
    wire [2:0]   s_axi_awsize;
    wire [1:0]   s_axi_awburst;
    wire         s_axi_awlock;
    wire [3:0]   s_axi_awcache;
    wire [2:0]   s_axi_awprot;
    wire [3:0]   s_axi_awqos;
    wire [3:0]   s_axi_awregion;
    wire         s_axi_awvalid;
    wire         s_axi_awready;

    // 写数据
    wire [127:0] s_axi_wdata;
    wire [15:0]  s_axi_wstrb;
    wire         s_axi_wlast;
    wire         s_axi_wvalid;
    wire         s_axi_wready;

    // 写响应
    wire [3:0]   s_axi_bid;
    wire [1:0]   s_axi_bresp;
    wire         s_axi_bvalid;
    wire         s_axi_bready;

    // 读地址
    wire [3:0]   s_axi_arid;
    wire [29:0]  s_axi_araddr;
    wire [7:0]   s_axi_arlen;
    wire [2:0]   s_axi_arsize;
    wire [1:0]   s_axi_arburst;
    wire         s_axi_arlock;
    wire [3:0]   s_axi_arcache;
    wire [2:0]   s_axi_arprot;
    wire [3:0]   s_axi_arqos;
    wire [3:0]   s_axi_arregion;
    wire         s_axi_arvalid;
    wire         s_axi_arready;

    // 读数据
    wire [3:0]   s_axi_rid;
    wire [127:0] s_axi_rdata;
    wire [1:0]   s_axi_rresp;
    wire         s_axi_rlast;
    wire         s_axi_rvalid;
    wire         s_axi_rready;

    // ==================================================================
    // Controller 例化 (自包含: 控制逻辑 + FIFO + AXI adapter)
    // ==================================================================
    ccd_frame_buf_ddr_ctrl #(
        .MAX_FRAMES      (MAX_FRAMES),
        .MAX_FRAME_DEPTH (MAX_FRAME_DEPTH),
        .AXI_ADDR_WIDTH  (AXI_ADDR_WIDTH),
        .AXI_DATA_WIDTH  (128),
        .AXI_BURST_LEN   (AXI_BURST_LEN),
        .FIFO_ADDR_WIDTH (FIFO_ADDR_WIDTH)
    ) u_ctrl (
        // 时钟与复位
        .i_ui_clk         (ui_clk),
        .i_adcclk         (i_adcclk),
        .i_rd_clk         (i_rd_clk),
        .i_rst_n          (ctrl_rst_n),

        // ADC 域 — 像素数据
        .i_wr_data        (i_wr_data),
        .i_wr_en          (i_wr_en),
        .i_pixel_type     (i_pixel_type),
        .i_frame_start    (i_frame_start),
        .i_frame_end      (i_frame_end),
        .i_image_width    (i_image_width),
        .i_image_height   (i_image_height),
        .i_read_mode      (i_read_mode),

        // RD 域 — FX2 读出接口
        .o_fifo_data      (o_fifo_data),
        .o_frame_num      (o_frame_num),
        .i_fifo_rd_en     (i_fifo_rd_en),
        .o_fifo_last_word (o_fifo_last_word),

        // 异常
        .o_frame_exception(o_frame_exception),

        // AXI4 Master → MIG
        .m_axi_awid       (s_axi_awid),
        .m_axi_awaddr     (s_axi_awaddr),
        .m_axi_awlen      (s_axi_awlen),
        .m_axi_awsize     (s_axi_awsize),
        .m_axi_awburst    (s_axi_awburst),
        .m_axi_awlock     (s_axi_awlock),
        .m_axi_awcache    (s_axi_awcache),
        .m_axi_awprot     (s_axi_awprot),
        .m_axi_awqos      (s_axi_awqos),
        .m_axi_awregion   (s_axi_awregion),
        .m_axi_awvalid    (s_axi_awvalid),
        .m_axi_awready    (s_axi_awready),

        .m_axi_wdata      (s_axi_wdata),
        .m_axi_wstrb      (s_axi_wstrb),
        .m_axi_wlast      (s_axi_wlast),
        .m_axi_wvalid     (s_axi_wvalid),
        .m_axi_wready     (s_axi_wready),

        .m_axi_bid        (s_axi_bid),
        .m_axi_bresp      (s_axi_bresp),
        .m_axi_bvalid     (s_axi_bvalid),
        .m_axi_bready     (s_axi_bready),

        .m_axi_arid       (s_axi_arid),
        .m_axi_araddr     (s_axi_araddr),
        .m_axi_arlen      (s_axi_arlen),
        .m_axi_arsize     (s_axi_arsize),
        .m_axi_arburst    (s_axi_arburst),
        .m_axi_arlock     (s_axi_arlock),
        .m_axi_arcache    (s_axi_arcache),
        .m_axi_arprot     (s_axi_arprot),
        .m_axi_arqos      (s_axi_arqos),
        .m_axi_arregion   (s_axi_arregion),
        .m_axi_arvalid    (s_axi_arvalid),
        .m_axi_arready    (s_axi_arready),

        .m_axi_rid        (s_axi_rid),
        .m_axi_rdata      (s_axi_rdata),
        .m_axi_rresp      (s_axi_rresp),
        .m_axi_rlast      (s_axi_rlast),
        .m_axi_rvalid     (s_axi_rvalid),
        .m_axi_rready     (s_axi_rready)
    );

    // ==================================================================
    // MIG 7-Series DDR3 Controller
    // ==================================================================
    mig_7series_0 u_mig (
        // DDR3 physical
        .ddr3_dq           (ddr3_dq),
        .ddr3_dqs_n        (ddr3_dqs_n),
        .ddr3_dqs_p        (ddr3_dqs_p),
        .ddr3_addr         (ddr3_addr),
        .ddr3_ba           (ddr3_ba),
        .ddr3_ras_n        (ddr3_ras_n),
        .ddr3_cas_n        (ddr3_cas_n),
        .ddr3_we_n         (ddr3_we_n),
        .ddr3_reset_n      (ddr3_reset_n),
        .ddr3_ck_p         (ddr3_ck_p),
        .ddr3_ck_n         (ddr3_ck_n),
        .ddr3_cke          (ddr3_cke),
        .ddr3_cs_n         (ddr3_cs_n),
        .ddr3_dm           (ddr3_dm),
        .ddr3_odt          (ddr3_odt),
        .init_calib_complete (init_calib_complete),
        // Clocks
        .sys_clk_i         (i_ddr3_clk100m),
        .clk_ref_i         (i_ddr3_clk200m_ref),
        .ui_clk            (ui_clk),
        .ui_clk_sync_rst   (ui_clk_sync_rst),
        .mmcm_locked       (mmcm_locked),
        // Reset
        .aresetn           (i_mig_rst_n),
        .sys_rst           (i_mig_rst_n),
        // Application interface ports
        .app_sr_req        (1'b0),
        .app_ref_req       (1'b0),
        .app_zq_req        (1'b0),
        .app_sr_active     (),
        .app_ref_ack       (),
        .app_zq_ack        (),
        // AXI write address
        .s_axi_awid        (s_axi_awid),
        .s_axi_awaddr      (s_axi_awaddr),
        .s_axi_awlen       (s_axi_awlen),
        .s_axi_awsize      (s_axi_awsize),
        .s_axi_awburst     (s_axi_awburst),
        .s_axi_awlock      (s_axi_awlock),
        .s_axi_awcache     (s_axi_awcache),
        .s_axi_awprot      (s_axi_awprot),
        .s_axi_awqos       (s_axi_awqos),
        .s_axi_awvalid     (s_axi_awvalid),
        .s_axi_awready     (s_axi_awready),
        // AXI write data
        .s_axi_wdata       (s_axi_wdata),
        .s_axi_wstrb       (s_axi_wstrb),
        .s_axi_wlast       (s_axi_wlast),
        .s_axi_wvalid      (s_axi_wvalid),
        .s_axi_wready      (s_axi_wready),
        // AXI write response
        .s_axi_bready      (s_axi_bready),
        .s_axi_bid         (s_axi_bid),
        .s_axi_bresp       (s_axi_bresp),
        .s_axi_bvalid      (s_axi_bvalid),
        // AXI read address
        .s_axi_arid        (s_axi_arid),
        .s_axi_araddr      (s_axi_araddr),
        .s_axi_arlen       (s_axi_arlen),
        .s_axi_arsize      (s_axi_arsize),
        .s_axi_arburst     (s_axi_arburst),
        .s_axi_arlock      (s_axi_arlock),
        .s_axi_arcache     (s_axi_arcache),
        .s_axi_arprot      (s_axi_arprot),
        .s_axi_arqos       (s_axi_arqos),
        .s_axi_arvalid     (s_axi_arvalid),
        .s_axi_arready     (s_axi_arready),
        // AXI read data
        .s_axi_rready      (s_axi_rready),
        .s_axi_rid         (s_axi_rid),
        .s_axi_rdata       (s_axi_rdata),
        .s_axi_rresp       (s_axi_rresp),
        .s_axi_rlast       (s_axi_rlast),
        .s_axi_rvalid      (s_axi_rvalid)
    );

endmodule

`timescale 1ns / 1ps
//==============================================================================
// Module : ccd_ddr
// Desc   : CCD 控制器顶层模块 (DDR 版本)。
//          实例化 ccd_driver（CCD 时序驱动）、ccd_frame_buf_ddr（DDR3 乒乓帧缓存）
//          和 ccd_frame_tx（帧发送模块），将 CCD 驱动输出的像素数据写入
//          DDR3 帧缓存，并通过帧发送模块转发至 EZ-USB Slave FIFO。
//
//          MIG (mig_7series_0) 需在本模块外部例化, 通过 AXI4 Master 接口与本模块连接。
//==============================================================================
module ccd_ddr #(
    parameter MAX_FRAME_DEPTH = 131072,  // 每帧最大像素数 (每个像素 2 字节)
    parameter MAX_FRAMES      = 8        // 最大缓存帧数
) (
    // ---- 系统 ----
    input  wire         i_ccd_clk,       // CCD 时序参考时钟 (100 MHz, 仅用于 CCD 时序信号分频)
    input  wire         i_rst_n,         // 异步复位, 低有效

    // ---- CCD 控制 ----
    input  wire         i_exposure,      // 曝光信号
    input  wire         i_freq_sel,      // SCLK 频率选择: 0 -> 100kHz, 1 -> 500kHz
    input  wire [6:0]   i_cdsclk_delay,  // CDSCLK 微调延时, 单位系统时钟周期

    // ---- 图像参数 ----
    input  wire [15:0]  i_image_width,   // 图像宽度 (pixels)
    input  wire [15:0]  i_image_height,  // 图像高度 (pixels)
    input  wire [3:0]   i_bevel_left,    // 左侧消隐
    input  wire [3:0]   i_bevel_top,     // 顶部消隐
    input  wire [3:0]   i_bevel_right,   // 右侧消隐
    input  wire [3:0]   i_bevel_bottom,  // 底部消隐
    input  wire [3:0]   i_blank_left,    // 左侧空白
    input  wire [3:0]   i_blank_right,   // 右侧空白
    input  wire [1:0]   i_read_mode,     // 读出模式: 0=line binning, 1=image
    input  wire         i_mock_mode,     // 调试模式: 屏蔽 ADC, 输出递增虚拟数据

    // ---- ADC 数据 ----
    input  wire [7:0]   i_adc_data,      // ADC 采样数据 (8bit)

    // ---- CCD 驱动信号 (对外输出, 连接 CCD 传感器) ----
    output wire o_adcclk,      // ADCCLK
    output wire o_p1v,         // P1V
    output wire o_p2v_tg,      // P2V / TG
    output wire o_p1h,         // P1H
    output wire o_p2h,         // P2H
    output wire o_p3h,         // P3H
    output wire o_p4h_sg,      // P4H / SG
    output wire o_rg,           // RG
    output wire o_cdsclk1,      // CDSCLK1
    output wire o_cdsclk2,      // CDSCLK2

    // ---- FX2 Slave FIFO 接口 ----
    input  wire         i_rd_clk,              // 读时钟 (FX2 Slave FIFO)
    input  wire         i_rd_clk_n,            // 读时钟反相 (来自 MMCM/PLL)
    input  wire         i_tx_frame_start,      // 帧发送触发 (下降沿启动)
    input  wire         i_slave_fifo_empty_n,  // FX2 Slave FIFO 空 (低有效)
    input  wire         i_slave_fifo_full_n,   // FX2 Slave FIFO 满 (低有效)
    output wire [15:0]  o_slave_fifo_data,     // 输出到 Slave FIFO 的数据
    output wire         o_slave_fifo_data_valid_n, // 数据有效 (低有效)
    output wire         o_slave_fifo_clk,      // 读时钟输出 (i_rd_clk 扇出)
    output wire         o_tx_last_n,        // 帧最后一字标志, 低有效脉冲

    // ---- 帧缓存状态 ----
    output wire [$clog2(MAX_FRAMES+1)-1:0]   o_frame_num,  // 帧缓存中可读帧数

    // ---- 异常 ----
    output wire         o_frame_exception,     // 帧异常脉冲

    // ---- MIG 接口 (ui_clk 域) ----
    input  wire         i_ui_clk,           // 来自外部 MIG 的 ui_clk
    input  wire         i_mmcm_locked,      // 来自外部 MIG: mmcm_locked
    input  wire         i_init_calib_complete, // 来自外部 MIG: init_calib_complete

    // ---- AXI4 Master 接口 (ui_clk 域, 连接外部 MIG S_AXI) ----
    // 写地址通道
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
    // 写数据通道
    output wire [127:0] M_AXI_WDATA,
    output wire [15:0]  M_AXI_WSTRB,
    output wire         M_AXI_WLAST,
    output wire         M_AXI_WVALID,
    input  wire         M_AXI_WREADY,
    // 写响应通道
    input  wire [3:0]   M_AXI_BID,
    input  wire [1:0]   M_AXI_BRESP,
    input  wire         M_AXI_BVALID,
    output wire         M_AXI_BREADY,
    // 读地址通道
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
    // 读数据通道
    input  wire [3:0]   M_AXI_RID,
    input  wire [127:0] M_AXI_RDATA,
    input  wire [1:0]   M_AXI_RRESP,
    input  wire         M_AXI_RLAST,
    input  wire         M_AXI_RVALID,
    output wire         M_AXI_RREADY
);

    // ==================================================================
    // 内部连线: ccd_driver → ccd_frame_buf_ddr
    // ==================================================================
    wire        adcclk_w;
    wire        data_valid_w;
    wire [1:0]  pixel_type_w;
    wire [15:0] pixel_data_w;
    wire        frame_start_w;
    wire        frame_end_w;

    // ==================================================================
    // 内部连线: ccd_frame_buf_ddr → ccd_frame_tx
    // ==================================================================
    wire [15:0] fifo_data_w;
    wire [$clog2(MAX_FRAMES+1)-1:0] fifo_frame_num_w;
    wire        fifo_prelast_w;
    wire        fifo_rd_en_w;

    // ==================================================================
    // 内部连线: DDR3 初始化状态 (mmcm_locked && init_calib_complete)
    // ==================================================================
    wire        ddr3_init_done = i_mmcm_locked && i_init_calib_complete;

    // ==================================================================
    // 控制器复位: 系统复位 AND DDR3 初始化完成
    //   ccd_driver / ccd_frame_buf_ddr / ccd_frame_tx 共享此复位
    // ==================================================================
    wire        ctrl_rst_n = i_rst_n && ddr3_init_done;

    // ==================================================================
    // ccd_driver 实例化
    // ==================================================================
    ccd_driver u_ccd_driver (
        .i_clk         (i_ccd_clk),
        .i_rst_n       (ctrl_rst_n),
        .i_exposure    (i_exposure),
        .i_freq_sel    (i_freq_sel),
        .i_cdsclk_delay(i_cdsclk_delay),
        .i_image_width (i_image_width),
        .i_image_height(i_image_height),
        .i_bevel_left  (i_bevel_left),
        .i_bevel_top   (i_bevel_top),
        .i_bevel_right (i_bevel_right),
        .i_bevel_bottom(i_bevel_bottom),
        .i_blank_left  (i_blank_left),
        .i_blank_right (i_blank_right),
        .i_read_mode   (i_read_mode),
        .i_mock_mode   (i_mock_mode),
        .i_adc_data    (i_adc_data),
        .o_adcclk      (adcclk_w),
        .o_p1v         (o_p1v),
        .o_p2v_tg      (o_p2v_tg),
        .o_p1h         (o_p1h),
        .o_p2h         (o_p2h),
        .o_p3h         (o_p3h),
        .o_p4h_sg      (o_p4h_sg),
        .o_rg          (o_rg),
        .o_cdsclk1     (o_cdsclk1),
        .o_cdsclk2     (o_cdsclk2),
        .o_data_valid  (data_valid_w),
        .o_pixel_type  (pixel_type_w),
        .o_pixel_data  (pixel_data_w),
        .o_frame_start (frame_start_w),
        .o_frame_end   (frame_end_w),
        .o_frame_idle  ()
    );

    // ADCCLK 对外输出
    assign o_adcclk = adcclk_w;

    // 帧缓存帧数 (直通 ccd_frame_buf_ddr.o_frame_num)
    assign o_frame_num = fifo_frame_num_w;

    // ==================================================================
    // ccd_frame_buf_ddr 实例化
    //   DDR3 帧缓存薄封装, 通过 AXI4 Master 连接外部 MIG。
    // ==================================================================
    ccd_frame_buf_ddr #(
        .MAX_FRAME_DEPTH(MAX_FRAME_DEPTH),
        .MAX_FRAMES     (MAX_FRAMES)
    ) u_ccd_frame_buf_ddr (
        .i_wr_clk          (adcclk_w),
        .i_rst_n           (ctrl_rst_n),
        .i_wr_data         (pixel_data_w),
        .i_wr_en           (data_valid_w),
        .i_pixel_type      (pixel_type_w),
        .i_frame_start     (frame_start_w),
        .i_frame_end       (frame_end_w),
        .i_image_width     (i_image_width),
        .i_image_height    (i_image_height),
        .i_read_mode       (i_read_mode),
        .i_rd_clk          (i_rd_clk),
        .o_fifo_data       (fifo_data_w),
        .o_frame_num       (fifo_frame_num_w),
        .o_fifo_prelast  (fifo_prelast_w),
        .i_fifo_rd_en      (fifo_rd_en_w),
        .o_frame_exception (o_frame_exception),
        .i_ui_clk          (i_ui_clk),
        .M_AXI_AWID        (M_AXI_AWID),
        .M_AXI_AWADDR      (M_AXI_AWADDR),
        .M_AXI_AWLEN       (M_AXI_AWLEN),
        .M_AXI_AWSIZE      (M_AXI_AWSIZE),
        .M_AXI_AWBURST     (M_AXI_AWBURST),
        .M_AXI_AWLOCK      (M_AXI_AWLOCK),
        .M_AXI_AWCACHE     (M_AXI_AWCACHE),
        .M_AXI_AWPROT      (M_AXI_AWPROT),
        .M_AXI_AWQOS       (M_AXI_AWQOS),
        .M_AXI_AWREGION    (M_AXI_AWREGION),
        .M_AXI_AWVALID     (M_AXI_AWVALID),
        .M_AXI_AWREADY     (M_AXI_AWREADY),
        .M_AXI_WDATA       (M_AXI_WDATA),
        .M_AXI_WSTRB       (M_AXI_WSTRB),
        .M_AXI_WLAST       (M_AXI_WLAST),
        .M_AXI_WVALID      (M_AXI_WVALID),
        .M_AXI_WREADY      (M_AXI_WREADY),
        .M_AXI_BID         (M_AXI_BID),
        .M_AXI_BRESP       (M_AXI_BRESP),
        .M_AXI_BVALID      (M_AXI_BVALID),
        .M_AXI_BREADY      (M_AXI_BREADY),
        .M_AXI_ARID        (M_AXI_ARID),
        .M_AXI_ARADDR      (M_AXI_ARADDR),
        .M_AXI_ARLEN       (M_AXI_ARLEN),
        .M_AXI_ARSIZE      (M_AXI_ARSIZE),
        .M_AXI_ARBURST     (M_AXI_ARBURST),
        .M_AXI_ARLOCK      (M_AXI_ARLOCK),
        .M_AXI_ARCACHE     (M_AXI_ARCACHE),
        .M_AXI_ARPROT      (M_AXI_ARPROT),
        .M_AXI_ARQOS       (M_AXI_ARQOS),
        .M_AXI_ARREGION    (M_AXI_ARREGION),
        .M_AXI_ARVALID     (M_AXI_ARVALID),
        .M_AXI_ARREADY     (M_AXI_ARREADY),
        .M_AXI_RID         (M_AXI_RID),
        .M_AXI_RDATA       (M_AXI_RDATA),
        .M_AXI_RRESP       (M_AXI_RRESP),
        .M_AXI_RLAST       (M_AXI_RLAST),
        .M_AXI_RVALID      (M_AXI_RVALID),
        .M_AXI_RREADY      (M_AXI_RREADY)
    );

    // FX2 Slave FIFO 时钟扇出
    assign o_slave_fifo_clk = i_rd_clk;

    // ==================================================================
    // ccd_frame_tx 实例化
    //   从 ccd_frame_buf_ddr 读取帧数据, 转发至 FX2 Slave FIFO。
    // ==================================================================

    ccd_frame_tx #(
        .MAX_FRAMES(MAX_FRAMES)
    ) u_ccd_frame_tx (
        .i_ext_clk             (i_rd_clk),
        .i_ext_clk_n           (i_rd_clk_n),
        .i_rst_n               (ctrl_rst_n),
        .i_frame_fifo_data     (fifo_data_w),
        .i_frame_fifo_num      (fifo_frame_num_w),
        .i_frame_fifo_prelast(fifo_prelast_w),
        .o_frame_fifo_rd_en    (fifo_rd_en_w),
        .o_slave_fifo_data     (o_slave_fifo_data),
        .o_slave_fifo_data_valid_n(o_slave_fifo_data_valid_n),
        .i_slave_fifo_empty_n  (i_slave_fifo_empty_n),
        .i_slave_fifo_full_n   (i_slave_fifo_full_n),
        .i_frame_start         (i_tx_frame_start),
        .o_tx_last_n        (o_tx_last_n)
    );

endmodule

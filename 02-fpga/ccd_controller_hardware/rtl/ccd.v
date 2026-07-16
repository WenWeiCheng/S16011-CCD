`timescale 1ns / 1ps
//==============================================================================
// Module : ccd
// Desc   : CCD 控制器顶层模块。
//          实例化 ccd_driver（CCD 时序驱动）、ccd_frame_buf（乒乓帧缓存）
//          和 ccd_frame_tx（帧发送模块），将 CCD 驱动输出的像素数据写入
//          帧缓存，并通过帧发送模块转发至 EZ-USB Slave FIFO。
//==============================================================================
module ccd #(
    parameter MAX_FRAME_DEPTH = 131072,  // 子 FIFO 物理深度
    parameter MAX_FRAMES      = 2         // 最大缓存帧数
) (
    // ---- 系统 ----
    input  wire         i_clk,           // 系统时钟 (100 MHz)
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
    input  wire         i_tx_frame_start,      // 帧发送触发 (下降沿启动)
    input  wire         i_slave_fifo_empty_n,  // FX2 Slave FIFO 空 (低有效)
    input  wire         i_slave_fifo_full_n,   // FX2 Slave FIFO 满 (低有效)
    output wire [15:0]  o_slave_fifo_data,     // 输出到 Slave FIFO 的数据
    output wire         o_slave_fifo_data_valid_n, // 数据有效 (低有效)
    output wire         o_frame_done_n,        // 帧发送完成 (低有效)
    // ---- 帧缓存状态 ----
    output wire [$clog2(MAX_FRAMES+1)-1:0]   o_frame_num,  // 帧缓存中可读帧数
    // ---- 异常 ----
    output wire         o_frame_exception      // 帧异常脉冲
);

    // ==================================================================
    // 内部连线: ccd_driver → ccd_frame_buf
    // ==================================================================
    wire        adcclk_w;
    wire        data_valid_w;
    wire [1:0]  pixel_type_w;
    wire [15:0] pixel_data_w;
    wire        frame_start_w;
    wire        frame_end_w;

    // ==================================================================
    // 内部连线: ccd_frame_buf → ccd_frame_tx
    // ==================================================================
    wire [15:0] fifo_data_w;
    wire [$clog2(MAX_FRAMES+1)-1:0] fifo_frame_num_w;
    wire        fifo_last_word_w;
    wire        fifo_rd_en_w;

    // ==================================================================
    // ccd_driver 实例化
    // ==================================================================
    ccd_driver u_ccd_driver (
        .i_clk         (i_clk),
        .i_rst_n       (i_rst_n),
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

    // 帧缓存帧数 (直通 ccd_frame_buf.o_frame_num)
    assign o_frame_num = fifo_frame_num_w;

    // ==================================================================
    // ccd_frame_buf 实例化
    //   输出 o_fifo_data / o_fifo_empty / o_fifo_last_word 等连接至
    //   ccd_frame_tx 内部, 不再直接对外暴露。
    // ==================================================================
    ccd_frame_buf #(
        .MAX_FRAME_DEPTH(MAX_FRAME_DEPTH),
        .MAX_FRAMES     (MAX_FRAMES)
    ) u_ccd_frame_buf (
        .i_adcclk          (adcclk_w),
        .i_rst_n           (i_rst_n),
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
        .o_fifo_last_word  (fifo_last_word_w),
        .i_fifo_rd_en      (fifo_rd_en_w),
        .o_frame_exception (o_frame_exception)
    );

    // ==================================================================
    // ccd_frame_tx 实例化
    //   从 ccd_frame_buf 读取帧数据, 转发至 FX2 Slave FIFO。
    // ==================================================================
    wire ext_clk_n = ~i_rd_clk;

    ccd_frame_tx #(
        .MAX_FRAMES(MAX_FRAMES)
    ) u_ccd_frame_tx (
        .i_ext_clk             (i_rd_clk),
        .i_ext_clk_n           (ext_clk_n),
        .i_rst_n               (i_rst_n),
        .i_frame_fifo_data     (fifo_data_w),
        .i_frame_fifo_num      (fifo_frame_num_w),
        .i_frame_fifo_last_word(fifo_last_word_w),
        .o_frame_fifo_rd_en    (fifo_rd_en_w),
        .o_slave_fifo_data     (o_slave_fifo_data),
        .o_slave_fifo_data_valid_n(o_slave_fifo_data_valid_n),
        .i_slave_fifo_empty_n  (i_slave_fifo_empty_n),
        .i_slave_fifo_full_n   (i_slave_fifo_full_n),
        .i_frame_start         (i_tx_frame_start),
        .o_frame_done_n        (o_frame_done_n)
    );

endmodule

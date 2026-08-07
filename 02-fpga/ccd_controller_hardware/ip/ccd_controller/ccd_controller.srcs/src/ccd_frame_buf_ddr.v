`timescale 1ns / 1ps
//==============================================================================
// Module : ccd_frame_buf_ddr
// Desc   : DDR 帧缓存顶层模块（薄封装）。
//          内部架构:
//            ccd_frame_buf_ddr_ctrl: 所有控制逻辑 + wr/rd FIFO + AXI adapter
//
//          MIG (mig_7series_0) 已移出至本模块外部, 通过 AXI4 Master 接口对接。
//
//          需要 Vivado 创建以下 IP:
//            wr_ddr3_fifo: FIFO Generator, 异步, 16bit×512(实511) 到 128bit×64(实63)
//            rd_ddr3_fifo: FIFO Generator, 异步, 128bit×64(实63) 到 16bit×512(实511)
//            mig_7series_0: MIG DDR3 Controller with axi interface (外部例化)
//          注: wr/rd FIFO 在 ccd_frame_buf_ddr_ctrl 内部例化。
//==============================================================================
module ccd_frame_buf_ddr #(
    parameter MAX_FRAME_DEPTH = 131072,  // 每帧最大像素数 (每个像素 2 字节)
    parameter MAX_FRAMES      = 64        // 最大缓存帧数
) (
    // ---- 写侧 (wr_clk 域) ----
    input  wire         i_wr_clk,
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
    output wire         o_fifo_prelast,
    output wire         o_frame_written,   // 帧完整写入 DDR 脉冲 (rd_clk 域)

    // ---- 异常 ----
    output wire         o_frame_exception,

    // ---- MIG 接口 (ui_clk 域) ----
    input  wire         i_ui_clk,           // 来自外部 MIG 的 ui_clk

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
    // 本地参数
    // ==================================================================
    localparam AXI_ADDR_WIDTH = 30;
    localparam AXI_BURST_LEN  = 8'd31;
    localparam FIFO_ADDR_WIDTH = 6;

    // ==================================================================
    // ctrl ↔ adapter 内部连线
    // ==================================================================
    wire                ctrl_wr_req;
    wire [29:0]         ctrl_wr_start;
    wire [29:0]         ctrl_wr_end;
    wire                ctrl_wr_idle;
    wire                ctrl_rd_req;
    wire [29:0]         ctrl_rd_start;
    wire [29:0]         ctrl_rd_end;
    wire                ctrl_rd_idle;
    wire [127:0]        wrfifo_dout;
    wire                wrfifo_rden;
    wire                rdfifo_wren;
    wire [127:0]        rdfifo_din;

    // ==================================================================
    // 图像参数变化检测 (ui_clk 域): read_mode / width / height 任一变化
    //   → 软复位电平 (展宽 ~41µs @100MHz, 覆盖最慢 adcclk 的复位同步)
    //   → 门控 frame_buf_rst_n, 复位 ctrl (三域) 与 adapter
    //   帧长度在复位释放后锁定, 参数变化即重新锁定新长度。
    // ==================================================================
    wire [33:0] img_param_now = {i_image_height, i_image_width, i_read_mode};
    reg  [33:0] img_param_shadow;
    reg         soft_rst;
    reg  [11:0] soft_rst_cnt;

    always @(posedge i_ui_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            img_param_shadow <= 34'd0;
            soft_rst         <= 1'b0;
            soft_rst_cnt     <= 12'd0;
        end else begin
            img_param_shadow <= img_param_now;
            if (img_param_shadow != img_param_now) begin
                soft_rst     <= 1'b1;
                soft_rst_cnt <= 12'hFFF;
            end else if (soft_rst) begin
                if (soft_rst_cnt == 12'h001) begin
                    soft_rst     <= 1'b0;
                    soft_rst_cnt <= 12'd0;
                end else begin
                    soft_rst_cnt <= soft_rst_cnt - 1'b1;
                end
            end
        end
    end

    // 门控复位: 系统复位 AND 非软复位 (soft_rst 为 ui_clk 域信号)
    wire frame_buf_rst_n = i_rst_n && ~soft_rst;

    // ==================================================================
    // Controller 例化 (控制逻辑 + wr/rd FIFO, AXI adapter 在外部)
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
        .i_ui_clk         (i_ui_clk),
        .i_wr_clk         (i_wr_clk),
        .i_rd_clk         (i_rd_clk),
        .i_rst_n          (frame_buf_rst_n),

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
        .o_fifo_prelast (o_fifo_prelast),
        .o_frame_written (o_frame_written),

        // 异常
        .o_frame_exception(o_frame_exception),

        // 写控制 → adapter
        .o_axi_wr_req       (ctrl_wr_req),
        .o_axi_wr_start_addr(ctrl_wr_start),
        .o_axi_wr_end_addr  (ctrl_wr_end),
        .i_axi_wr_idle      (ctrl_wr_idle),

        // 读控制 → adapter
        .o_axi_rd_req       (ctrl_rd_req),
        .o_axi_rd_start_addr(ctrl_rd_start),
        .o_axi_rd_end_addr  (ctrl_rd_end),
        .i_axi_rd_idle      (ctrl_rd_idle),

        // wr-fifo ↔ adapter
        .o_wrfifo_dout      (wrfifo_dout),
        .i_wrfifo_rden      (wrfifo_rden),

        // rd-fifo ↔ adapter
        .i_rdfifo_wren      (rdfifo_wren),
        .i_rdfifo_din       (rdfifo_din)
    );

    // ==================================================================
    // AXI4 Adapter 例化 (ctrl ↔ 外部 MIG)
    // ==================================================================
    ccd_frame_buf_ddr_axi_adapter #(
        .AXI_DATA_WIDTH (128),
        .AXI_ADDR_WIDTH (30),
        .AXI_ID_WIDTH   (4),
        .AXI_ID         (4'b0000),
        .AXI_BURST_LEN  (8'd31)
    ) u_adapter (
        .i_clk              (i_ui_clk),
        .i_rst_n            (frame_buf_rst_n),
        .i_axi_wr_req       (ctrl_wr_req),
        .i_axi_wr_start_addr(ctrl_wr_start),
        .i_axi_wr_end_addr  (ctrl_wr_end),
        .o_axi_wr_idle      (ctrl_wr_idle),
        .i_axi_rd_req       (ctrl_rd_req),
        .i_axi_rd_start_addr(ctrl_rd_start),
        .i_axi_rd_end_addr  (ctrl_rd_end),
        .o_axi_rd_idle      (ctrl_rd_idle),
        .o_wrfifo_rden      (wrfifo_rden),
        .i_wrfifo_dout      (wrfifo_dout),
        .o_rdfifo_wren      (rdfifo_wren),
        .o_rdfifo_din       (rdfifo_din),
        .m_axi_awid         (M_AXI_AWID),
        .m_axi_awaddr       (M_AXI_AWADDR),
        .m_axi_awlen        (M_AXI_AWLEN),
        .m_axi_awsize       (M_AXI_AWSIZE),
        .m_axi_awburst      (M_AXI_AWBURST),
        .m_axi_awlock       (M_AXI_AWLOCK),
        .m_axi_awcache      (M_AXI_AWCACHE),
        .m_axi_awprot       (M_AXI_AWPROT),
        .m_axi_awqos        (M_AXI_AWQOS),
        .m_axi_awregion     (M_AXI_AWREGION),
        .m_axi_awvalid      (M_AXI_AWVALID),
        .m_axi_awready      (M_AXI_AWREADY),
        .m_axi_wdata        (M_AXI_WDATA),
        .m_axi_wstrb        (M_AXI_WSTRB),
        .m_axi_wlast        (M_AXI_WLAST),
        .m_axi_wvalid       (M_AXI_WVALID),
        .m_axi_wready       (M_AXI_WREADY),
        .m_axi_bid          (M_AXI_BID),
        .m_axi_bresp        (M_AXI_BRESP),
        .m_axi_bvalid       (M_AXI_BVALID),
        .m_axi_bready       (M_AXI_BREADY),
        .m_axi_arid         (M_AXI_ARID),
        .m_axi_araddr       (M_AXI_ARADDR),
        .m_axi_arlen        (M_AXI_ARLEN),
        .m_axi_arsize       (M_AXI_ARSIZE),
        .m_axi_arburst      (M_AXI_ARBURST),
        .m_axi_arlock       (M_AXI_ARLOCK),
        .m_axi_arcache      (M_AXI_ARCACHE),
        .m_axi_arprot       (M_AXI_ARPROT),
        .m_axi_arqos        (M_AXI_ARQOS),
        .m_axi_arregion     (M_AXI_ARREGION),
        .m_axi_arvalid      (M_AXI_ARVALID),
        .m_axi_arready      (M_AXI_ARREADY),
        .m_axi_rid          (M_AXI_RID),
        .m_axi_rdata        (M_AXI_RDATA),
        .m_axi_rresp        (M_AXI_RRESP),
        .m_axi_rlast        (M_AXI_RLAST),
        .m_axi_rvalid       (M_AXI_RVALID),
        .m_axi_rready       (M_AXI_RREADY)
    );

endmodule

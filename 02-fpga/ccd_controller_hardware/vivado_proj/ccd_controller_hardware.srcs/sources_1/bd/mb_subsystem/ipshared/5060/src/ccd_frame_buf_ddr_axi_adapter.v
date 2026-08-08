`timescale 1ns / 1ps
//==============================================================================
// Module : ccd_frame_buf_ddr_axi_adapter
// Desc   : AXI4 突发事务适配器, controller 驱动模式。
//          接收 controller 的 axi_wr_req/axi_rd_req 脉冲,
//          完成一次 AXI 突发写入或读取, 数据在 wr-fifo 和 rd-fifo 间传输。
//
// 注意: start_addr / end_addr 必须 16 字节对齐 (低 4 位为 0),
//       且 (end_addr - start_addr) 必须是 16 的倍数。
//       AXI 数据宽度为 128-bit (16 字节), awsize/arsize = 4,
//       地址差 >> 4 得到突发拍数, 不满足对齐条件将导致数据错误。
//
//  写状态机 (fifo2ddr):
//    S_IDLE → S_WR_ADDR     : axi_wr_req && axi_wr_idle
//    S_WR_ADDR → S_WR_DATA  : m_axi_awready
//    S_WR_DATA → S_WR_RESP  : m_axi_wlast && m_axi_wready
//    S_WR_RESP → S_IDLE     : m_axi_bvalid && m_axi_bresp==0
//
//  读状态机 (ddr2fifo):
//    S_IDLE → S_RD_ADDR     : axi_rd_req && axi_rd_idle
//    S_RD_ADDR → S_RD_RESP  : m_axi_arready
//    S_RD_RESP → S_IDLE     : m_axi_rlast && m_axi_rvalid
//
//  axi_wr_idle/axi_rd_idle: 1=空闲, 0=忙碌
//==============================================================================
module ccd_frame_buf_ddr_axi_adapter #(
    parameter AXI_DATA_WIDTH  = 128,
    parameter AXI_ADDR_WIDTH  = 30,
    parameter AXI_ID_WIDTH    = 4,
    parameter AXI_ID          = 4'b0000,
    parameter AXI_BURST_LEN   = 8'd31   // burst length = BURST_LEN+1 = 32
) (
    input  wire                     i_clk,
    input  wire                     i_rst_n,

    // ---- Controller 接口 ----
    // 注意: start_addr / end_addr 必须 16 字节对齐 (低 4 位为 0),
    //       且差值须为 16 的倍数, 详见文件头说明。
    input  wire                     i_axi_wr_req,
    input  wire [AXI_ADDR_WIDTH-1:0] i_axi_wr_start_addr,
    input  wire [AXI_ADDR_WIDTH-1:0] i_axi_wr_end_addr,
    output reg                      o_axi_wr_idle,

    input  wire                     i_axi_rd_req,
    input  wire [AXI_ADDR_WIDTH-1:0] i_axi_rd_start_addr,
    input  wire [AXI_ADDR_WIDTH-1:0] i_axi_rd_end_addr,
    output reg                      o_axi_rd_idle,

    // ---- FIFO 接口 (wr-fifo: 128-bit 读侧) ----
    output reg                      o_wrfifo_rden,
    input  wire [AXI_DATA_WIDTH-1:0] i_wrfifo_dout,

    // ---- FIFO 接口 (rd-fifo: 128-bit 写侧) ----
    output reg                      o_rdfifo_wren,
    output reg [AXI_DATA_WIDTH-1:0] o_rdfifo_din,

    // ---- AXI4 写地址 ----
    output     [AXI_ID_WIDTH-1:0]   m_axi_awid,
    output reg [AXI_ADDR_WIDTH-1:0] m_axi_awaddr,
    output     [7:0]                m_axi_awlen,
    output     [2:0]                m_axi_awsize,
    output     [1:0]                m_axi_awburst,
    output                          m_axi_awlock,
    output     [3:0]                m_axi_awcache,
    output     [2:0]                m_axi_awprot,
    output     [3:0]                m_axi_awqos,
    output     [3:0]                m_axi_awregion,
    output reg                      m_axi_awvalid,
    input  wire                     m_axi_awready,

    // ---- AXI4 写数据 ----
    output     [AXI_DATA_WIDTH-1:0] m_axi_wdata,
    output     [AXI_DATA_WIDTH/8-1:0] m_axi_wstrb,
    output reg                      m_axi_wlast,
    output reg                      m_axi_wvalid,
    input  wire                     m_axi_wready,

    // ---- AXI4 写响应 ----
    input  wire [AXI_ID_WIDTH-1:0] m_axi_bid,
    input  wire [1:0]              m_axi_bresp,
    input  wire                     m_axi_bvalid,
    output reg                      m_axi_bready,

    // ---- AXI4 读地址 ----
    output     [AXI_ID_WIDTH-1:0]   m_axi_arid,
    output reg [AXI_ADDR_WIDTH-1:0] m_axi_araddr,
    output     [7:0]                m_axi_arlen,
    output     [2:0]                m_axi_arsize,
    output     [1:0]                m_axi_arburst,
    output                          m_axi_arlock,
    output     [3:0]                m_axi_arcache,
    output     [2:0]                m_axi_arprot,
    output     [3:0]                m_axi_arqos,
    output     [3:0]                m_axi_arregion,
    output reg                      m_axi_arvalid,
    input  wire                     m_axi_arready,

    // ---- AXI4 读数据 ----
    input  wire [AXI_ID_WIDTH-1:0]  m_axi_rid,
    input  wire [AXI_DATA_WIDTH-1:0] m_axi_rdata,
    input  wire [1:0]               m_axi_rresp,
    input  wire                     m_axi_rlast,
    input  wire                     m_axi_rvalid,
    output reg                      m_axi_rready
);

    // ==================================================================
    // 本地参数
    // ==================================================================
    localparam DATA_SIZE = $clog2(AXI_DATA_WIDTH / 8 - 1); // 128bit → 4

    // 写状态机编码
    localparam S_WR_IDLE      = 3'd0;
    localparam S_WR_ADDR      = 3'd1;
    localparam S_WR_DATA_PRE  = 3'd4;
    localparam S_WR_DATA      = 3'd2;
    localparam S_WR_RESP      = 3'd3;

    // 读状态机编码
    localparam S_RD_IDLE  = 2'd0;
    localparam S_RD_ADDR  = 2'd1;
    localparam S_RD_RESP  = 2'd2;

    // ==================================================================
    // ---- 全部 reg 声明 ----
    // ==================================================================
    // 上升沿检测
    reg  i_axi_wr_req_d, i_axi_rd_req_d;

    // 写通道
    reg [2:0]  wr_state;
    reg [2:0]  wr_next_state;
    reg [AXI_ADDR_WIDTH-1:0] wr_addr_reg;          // 当前写地址游标
    reg [AXI_ADDR_WIDTH-1:0] wr_end_addr_reg;      // 结束地址 (不含)
    reg [7:0]  wr_beats;                            // 突发总拍数
    reg [7:0]  wr_beat_cnt;                         // 当前已发送拍数

    // 读通道
    reg [1:0]  rd_state;
    reg [1:0]  rd_next_state;
    reg [AXI_ADDR_WIDTH-1:0] rd_addr_reg;
    reg [AXI_ADDR_WIDTH-1:0] rd_end_addr_reg;
    reg [7:0]  rd_beats;
    reg [7:0]  rd_beat_cnt;

    // ==================================================================
    // ---- 全部 wire 声明 ----
    // ==================================================================
    // 上升沿检测
    wire wr_req_rise, rd_req_rise;

    // AWLEN / ARLEN 计算: beats = (end_addr - start_addr) / 16
    wire [7:0] wr_awlen = (wr_beats > 0) ? (wr_beats - 1) : 8'd0;
    wire [7:0] rd_arlen = (rd_beats > 0) ? (rd_beats - 1) : 8'd0;

    // ==================================================================
    // AXI4 固定信号 (assign)
    // ==================================================================
    assign m_axi_awid    = AXI_ID[AXI_ID_WIDTH-1:0];
    assign m_axi_awsize  = DATA_SIZE;
    assign m_axi_awburst = 2'b01;  // INCR
    assign m_axi_awlock  = 1'b0;
    assign m_axi_awcache = 4'b0000;
    assign m_axi_awprot  = 3'b000;
    assign m_axi_awqos   = 4'b0000;
    assign m_axi_awregion= 4'b0000;

    assign m_axi_arid    = AXI_ID[AXI_ID_WIDTH-1:0];
    assign m_axi_arsize  = DATA_SIZE;
    assign m_axi_arburst = 2'b01;
    assign m_axi_arlock  = 1'b0;
    assign m_axi_arcache = 4'b0000;
    assign m_axi_arprot  = 3'b000;
    assign m_axi_arqos   = 4'b0000;
    assign m_axi_arregion= 4'b0000;

    assign m_axi_wstrb   = {AXI_DATA_WIDTH/8{1'b1}};
    assign m_axi_wdata   = i_wrfifo_dout;

    assign m_axi_awlen = wr_awlen;
    assign m_axi_arlen = rd_arlen;

    // ==================================================================
    // 上升沿检测: req 单周期脉冲触发事务
    // ==================================================================
    always @(posedge i_clk) begin
        i_axi_wr_req_d <= i_axi_wr_req;
        i_axi_rd_req_d <= i_axi_rd_req;
    end
    assign wr_req_rise = !i_axi_wr_req_d && i_axi_wr_req;
    assign rd_req_rise = !i_axi_rd_req_d && i_axi_rd_req;

    // ==================================================================
    // 写状态机 — 三段式
    // ==================================================================

    // ---- 第一段: 状态寄存器 ----
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) wr_state <= S_WR_IDLE;
        else          wr_state <= wr_next_state;
    end

    // ---- 第二段: 次态组合逻辑 ----
    always @(*) begin
        wr_next_state = wr_state;
        case (wr_state)
            S_WR_IDLE: begin
                if (wr_req_rise && o_axi_wr_idle)
                    wr_next_state = S_WR_ADDR;
            end
            S_WR_ADDR: begin
                if (m_axi_awready && m_axi_awvalid)
                    wr_next_state = S_WR_DATA_PRE;
            end
            S_WR_DATA_PRE: begin
                wr_next_state = S_WR_DATA;
            end
            S_WR_DATA: begin
                if (m_axi_wvalid && m_axi_wready && m_axi_wlast)
                    wr_next_state = S_WR_RESP;
                else if(m_axi_wready && m_axi_wvalid)
                    wr_next_state = S_WR_DATA_PRE;
            end
            S_WR_RESP: begin
                if (m_axi_bvalid && (m_axi_bresp == 2'b00) &&
                    (m_axi_bid == AXI_ID[AXI_ID_WIDTH-1:0]))
                    wr_next_state = S_WR_IDLE;
            end
            default: wr_next_state = S_WR_IDLE;
        endcase
    end

    // ---- 第三段: 输出时序逻辑 ----
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            o_axi_wr_idle  <= 1'b1;
            m_axi_awvalid  <= 1'b0;
            m_axi_awaddr   <= 0;
            m_axi_wvalid   <= 1'b0;
            m_axi_wlast    <= 1'b0;
            m_axi_bready   <= 1'b0;
            o_wrfifo_rden  <= 1'b0;
            wr_addr_reg    <= 0;
            wr_end_addr_reg<= 0;
            wr_beats       <= 0;
            wr_beat_cnt    <= 0;
        end else begin
            o_wrfifo_rden <= 1'b0;
            m_axi_awvalid <= 1'b0;

            case (wr_state)
                // ----------------------------------------------------------
                // S_WR_IDLE: 等待控制器请求
                // ----------------------------------------------------------
                S_WR_IDLE: begin
                    o_axi_wr_idle <= 1'b1;
                    m_axi_bready  <= 1'b0;
                    m_axi_wvalid  <= 1'b0;
                    m_axi_wlast   <= 1'b0;
                    wr_beat_cnt   <= 0;

                    if (wr_req_rise && o_axi_wr_idle) begin
                        wr_addr_reg    <= i_axi_wr_start_addr;
                        wr_end_addr_reg<= i_axi_wr_end_addr;
                        wr_beats       <= (i_axi_wr_end_addr - i_axi_wr_start_addr) >> 4;
                        o_axi_wr_idle  <= 1'b0;
                        m_axi_awaddr   <= i_axi_wr_start_addr;
                        m_axi_awvalid  <= 1'b1;
                    end
                end

                // ----------------------------------------------------------
                // S_WR_ADDR: 发送写地址
                // ----------------------------------------------------------
                S_WR_ADDR: begin
                    o_axi_wr_idle <= 1'b0;

                    if (m_axi_awready && m_axi_awvalid) begin
                        // 地址握手完成, 开始发送数据
                        o_wrfifo_rden <= 1'b1;  // 预读第一笔数据
                    end else begin
                        m_axi_awvalid <= 1'b1;
                    end
                end

                S_WR_DATA_PRE: begin
                    o_wrfifo_rden <= 0;
                    m_axi_wvalid <= 1'b1;
                    if (wr_beat_cnt == (wr_beats-1)) begin
                        m_axi_wlast <= 1'b1;
                    end
                end

                // ----------------------------------------------------------
                // S_WR_DATA: 发送写数据
                // ----------------------------------------------------------
                S_WR_DATA: begin
                    o_axi_wr_idle <= 1'b0;
                    m_axi_bready  <= 1'b1;

                    if (m_axi_wvalid && m_axi_wready) begin
                        // 当前拍完成
                        if (m_axi_wlast) begin
                            m_axi_wvalid <= 1'b0;
                            m_axi_wlast  <= 1'b0;
                        end else begin
                            wr_beat_cnt  <= wr_beat_cnt + 1;
                            o_wrfifo_rden <= (wr_beat_cnt < wr_beats) ? 1'b1 : 1'b0;
                            m_axi_wvalid <= 1'b0;
                            m_axi_wlast  <= 1'b0;
                        end
                    end

                end

                // ----------------------------------------------------------
                // S_WR_RESP: 等待写响应
                // ----------------------------------------------------------
                S_WR_RESP: begin
                    m_axi_wvalid <= 1'b0;
                    m_axi_wlast  <= 1'b0;
                    m_axi_bready <= 1'b1;

                    if (m_axi_bvalid && (m_axi_bresp == 2'b00) &&
                        (m_axi_bid == AXI_ID[AXI_ID_WIDTH-1:0])) begin
                        m_axi_bready  <= 1'b0;
                        o_axi_wr_idle <= 1'b1;
                    end
                end

                default: begin
                    o_axi_wr_idle <= 1'b1;
                    m_axi_awvalid <= 1'b0;
                    m_axi_wvalid  <= 1'b0;
                    m_axi_wlast   <= 1'b0;
                    m_axi_bready  <= 1'b0;
                    o_wrfifo_rden <= 1'b0;
                end
            endcase
        end
    end

    // ==================================================================
    // 读状态机 — 三段式
    // ==================================================================

    // ---- 第一段: 状态寄存器 ----
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) rd_state <= S_RD_IDLE;
        else          rd_state <= rd_next_state;
    end

    // ---- 第二段: 次态组合逻辑 ----
    always @(*) begin
        rd_next_state = rd_state;
        case (rd_state)
            S_RD_IDLE: begin
                if (rd_req_rise && o_axi_rd_idle)
                    rd_next_state = S_RD_ADDR;
            end
            S_RD_ADDR: begin
                if (m_axi_arready && m_axi_arvalid)
                    rd_next_state = S_RD_RESP;
            end
            S_RD_RESP: begin
                if (m_axi_rvalid && m_axi_rready && m_axi_rlast)
                    rd_next_state = S_RD_IDLE;
            end
            default: rd_next_state = S_RD_IDLE;
        endcase
    end

    // ---- 第三段: 输出时序逻辑 ----
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            o_axi_rd_idle  <= 1'b1;
            m_axi_arvalid  <= 1'b0;
            m_axi_araddr   <= 0;
            m_axi_rready   <= 1'b0;
            o_rdfifo_wren  <= 1'b0;
            o_rdfifo_din   <= 0;
            rd_addr_reg    <= 0;
            rd_end_addr_reg<= 0;
            rd_beats       <= 0;
            rd_beat_cnt    <= 0;
        end else begin
            o_rdfifo_wren <= 1'b0;
            o_rdfifo_din  <= {AXI_DATA_WIDTH{1'b0}};

            case (rd_state)
                // ----------------------------------------------------------
                // S_RD_IDLE: 等待控制器请求
                // ----------------------------------------------------------
                S_RD_IDLE: begin
                    o_axi_rd_idle <= 1'b1;
                    m_axi_rready  <= 1'b0;
                    m_axi_arvalid <= 1'b0;
                    rd_beat_cnt   <= 0;

                    if (rd_req_rise && o_axi_rd_idle) begin
                        rd_addr_reg    <= i_axi_rd_start_addr;
                        rd_end_addr_reg<= i_axi_rd_end_addr;
                        rd_beats       <= (i_axi_rd_end_addr - i_axi_rd_start_addr) >> 4;
                        o_axi_rd_idle  <= 1'b0;
                        m_axi_araddr   <= i_axi_rd_start_addr;
                        m_axi_arvalid  <= 1'b1;
                    end
                end

                // ----------------------------------------------------------
                // S_RD_ADDR: 发送读地址
                // ----------------------------------------------------------
                S_RD_ADDR: begin
                    o_axi_rd_idle <= 1'b0;

                    if (m_axi_arready && m_axi_arvalid) begin
                        // 地址握手完成, 等待读数据
                        m_axi_arvalid <= 1'b0;
                    end else begin
                        m_axi_arvalid <= 1'b1;
                    end
                end

                // ----------------------------------------------------------
                // S_RD_RESP: 接收读数据
                // ----------------------------------------------------------
                S_RD_RESP: begin
                    o_axi_rd_idle <= 1'b0;
                    m_axi_rready  <= 1'b1;

                    if (m_axi_rvalid && m_axi_rready) begin
                        rd_beat_cnt  <= rd_beat_cnt + 1;
                        o_rdfifo_wren <= (rd_beat_cnt < rd_beats) ? 1'b1 : 1'b0;
                        // 写入 rd-fifo
                        o_rdfifo_wren <= 1'b1;
                        o_rdfifo_din  <= m_axi_rdata;

                        if (m_axi_rlast) begin
                            m_axi_rready  <= 1'b0;
                            o_axi_rd_idle <= 1'b1;
                        end
                    end
                end

                default: begin
                    o_axi_rd_idle <= 1'b1;
                    m_axi_arvalid <= 1'b0;
                    m_axi_rready  <= 1'b0;
                    o_rdfifo_wren <= 1'b0;
                    o_rdfifo_din  <= {AXI_DATA_WIDTH{1'b0}};
                end
            endcase
        end
    end

endmodule

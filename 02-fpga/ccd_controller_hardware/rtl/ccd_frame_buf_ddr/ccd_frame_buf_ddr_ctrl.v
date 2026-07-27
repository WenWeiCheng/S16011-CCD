`timescale 1ns / 1ps
//==============================================================================
// Module : ccd_frame_buf_ddr_ctrl
// Desc   : DDR 帧缓存控制器（多时钟域自包含模块）。
//          内部集成:
//            - i_adcclk 域: 边沿检测、像素计数、帧验证、frame_exception
//            - i_ui_clk 域: WR/RD 状态机、block 管理、per-frame depth 计算
//            - i_rd_clk 域: o_fifo_prelast、o_frame_num
//            - 跨域 CDC
//            - wr_ddr3_fifo / rd_ddr3_fifo (Xilinx FIFO IP)
//            - ccd_frame_buf_ddr_axi_adapter
//
//  写状态机 (三段式):
//    S_WR_IDLE → S_WR_WAIT  : frame_start_rise_ui && wr_not_full
//    S_WR_WAIT → S_WR_FIFO2AXI: wr_burst_ready || wr_partial_ready
//    S_WR_FIFO2AXI → S_WR_WAIT: !axi_wr_idle
//    S_WR_WAIT → S_WR_IDLE  : frame_ended && wrfifo_empty
//
//  读状态机 (三段式):
//    S_RD_IDLE → S_RD_AXI2FIFO: rd_block_id!=wr_block_id && (条件满足)
//    S_RD_AXI2FIFO → S_RD_IDLE: !axi_rd_idle
//==============================================================================
module ccd_frame_buf_ddr_ctrl #(
    parameter MAX_FRAMES       = 8,
    parameter MAX_FRAME_DEPTH  = 131072,
    parameter AXI_ADDR_WIDTH   = 30,
    parameter AXI_DATA_WIDTH   = 128,
    parameter AXI_BURST_LEN    = 8'd31,
    parameter FIFO_ADDR_WIDTH  = 6
) (
    // ==================================================================
    // 时钟与复位
    // ==================================================================
    input  wire                            i_ui_clk,          // MIG ui_clk
    input  wire                            i_adcclk,          // ADC 像素时钟
    input  wire                            i_rd_clk,          // FX2 读出时钟
    input  wire                            i_rst_n,           // 系统复位（低有效, 顶层已门控 DDR 初始化完成）

    // ==================================================================
    // ADC 域输入 — 像素数据
    // ==================================================================
    input  wire [15:0]                     i_wr_data,
    input  wire                            i_wr_en,
    input  wire [1:0]                      i_pixel_type,
    input  wire                            i_frame_start,
    input  wire                            i_frame_end,
    input  wire [15:0]                     i_image_width,
    input  wire [15:0]                     i_image_height,
    input  wire [1:0]                      i_read_mode,

    // ==================================================================
    // RD 域输出 — FX2 读出接口
    // ==================================================================
    output wire [15:0]                     o_fifo_data,
    output wire [$clog2(MAX_FRAMES+1)-1:0] o_frame_num,
    input  wire                            i_fifo_rd_en,
    output wire                            o_fifo_prelast,

    // ==================================================================
    // 异常输出 (adcclk 域)
    // ==================================================================
    output wire                            o_frame_exception,

    // ==================================================================
    // 控制器→适配器: 写控制
    // ==================================================================
    output reg                             o_axi_wr_req,
    output reg  [AXI_ADDR_WIDTH-1:0]       o_axi_wr_start_addr,
    output reg  [AXI_ADDR_WIDTH-1:0]       o_axi_wr_end_addr,
    input  wire                            i_axi_wr_idle,

    // ==================================================================
    // 控制器→适配器: 读控制
    // ==================================================================
    output reg                             o_axi_rd_req,
    output reg  [AXI_ADDR_WIDTH-1:0]       o_axi_rd_start_addr,
    output reg  [AXI_ADDR_WIDTH-1:0]       o_axi_rd_end_addr,
    input  wire                            i_axi_rd_idle,

    // ==================================================================
    // wr-fifo ↔ 适配器 (128-bit 接口)
    // ==================================================================
    output wire [AXI_DATA_WIDTH-1:0]       o_wrfifo_dout,
    input  wire                            i_wrfifo_rden,

    // ==================================================================
    // rd-fifo ↔ 适配器 (128-bit 接口)
    // ==================================================================
    input  wire                            i_rdfifo_wren,
    input  wire [AXI_DATA_WIDTH-1:0]       i_rdfifo_din
);

    // ==================================================================
    // 本地参数
    // ==================================================================
    localparam FRAME_NUM_W          = $clog2(MAX_FRAMES + 1);
    localparam AXI_DATA_BYTES       = AXI_DATA_WIDTH / 8;              // 16
    localparam MAX_FRAME_DEPTH_BYTES= MAX_FRAME_DEPTH * 2;
    localparam BLOCK_ID_W           = $clog2(MAX_FRAMES) + 1;
    localparam BLOCK_ID_LOWER_W     = $clog2(MAX_FRAMES);
    localparam BYTE_COUNT_W         = $clog2(MAX_FRAME_DEPTH_BYTES)+1; //  多一位以防溢出
    localparam BURST_BYTES          = (AXI_BURST_LEN + 8'd1) * AXI_DATA_BYTES; // 512
    localparam BURST_UNITS          = (AXI_BURST_LEN + 8'd1);          // 32
    // Xilinx FIFO 实际可用深度 = 配置深度 - 1
    localparam FIFO_DEPTH           = 2**FIFO_ADDR_WIDTH - 1;          // 63

    // 状态编码
    localparam S_WR_IDLE      = 2'd0;
    localparam S_WR_WAIT      = 2'd1;
    localparam S_WR_FIFO2AXI  = 2'd2;

    localparam S_RD_IDLE      = 1'd0;
    localparam S_RD_AXI2FIFO  = 1'd1;

    // ==================================================================
    // ---- 全部 wire / reg 声明 (按域分组) ----
    // ==================================================================

    // ---- i_adcclk 域: 边沿检测 ----
    reg  frame_start_d, frame_end_d;
    reg frame_start_rise, frame_end_rise;

    // ---- i_adcclk 域: frame_active + 像素计数器 + frame_valid ----
    reg         frame_active;
    reg  [31:0] pixel_cnt;
    reg  [31:0] frame_depth_reg;
    wire [31:0] frame_depth_w;
    reg         wr_frame_valid_adcclk;

    // ---- i_adcclk 域: wr-fifo 写 + o_frame_exception ----
    wire wrfifo_wr_en;
    reg  frame_exception_adcclk;

    // ---- i_adcclk 域: per-frame depth FIFO ----
    //   帧有效结束时记录 pixel_cnt；写后稳定不变，CDC 到 rd_clk。
    reg  [31:0] frame_depth_fifo [0:MAX_FRAMES-1];
    reg  [BLOCK_ID_LOWER_W:0] depth_wr_ptr;       // MSB 回绕位
    reg                        rst_n_adcclk;        // i_rst_n 同步到 adcclk 域 (1 拍)

    // ---- wr-fifo (16→128) 接口 ----
    wire         wrfifo_empty;
    wire [FIFO_ADDR_WIDTH-1:0] wrfifo_rdcnt;

    // ---- rd-fifo (128→16) 接口 ----
    wire         rdfifo_full;
    wire         rdfifo_empty;
    wire [15:0]  rdfifo_dout;
    wire [FIFO_ADDR_WIDTH-1:0] rdfifo_wrcnt;

    // ---- CDC: i_adcclk → i_ui_clk ----
    reg  [1:0] frame_active_sync;
    wire       frame_active_ui;
    reg  [2:0] frame_start_sync;
    reg        frame_start_sync_d;
    wire       frame_start_rise_ui;
    reg  [2:0] wr_frame_valid_sync;

    // ---- ui_clk 域: DDR 块管理 ----
    reg [BLOCK_ID_W-1:0]       ddr_wr_block_id;
    reg [BLOCK_ID_W-1:0]       ddr_rd_block_id;
    reg [AXI_ADDR_WIDTH-1:0]   ddr_block_end_ptr [0:MAX_FRAMES-1];
    reg [BYTE_COUNT_W-1:0]     ddr_wr_byte_count;
    reg [BYTE_COUNT_W-1:0]     ddr_rd_byte_count;
    reg                        wr_frame_inc_toggle;  // pulse CDC toggle: ui_clk → rd_clk

    // ---- ui_clk 域: 写状态机 ----
    reg [1:0]  wr_state, wr_state_next;
    reg        wr_burst_is_partial;
    reg [BYTE_COUNT_W-1:0] wr_partial_bytes_latched;

    // ---- ui_clk 域: 读状态机 ----
    reg        rd_state, rd_state_next;

    // ---- ui_clk 域: 边沿检测 ----
    reg        axi_wr_idle_d1;
    reg        axi_rd_idle_d1;

    // ---- ui_clk 域: 帧计数脉冲 ----
    reg        wr_frame_inc;
    reg        rd_frame_dec;

    // ---- CDC: ui_clk → rd_clk (wr_frame_inc 脉冲) ----
    reg  [2:0] wr_frame_inc_toggle_sync;
    reg        wr_frame_inc_toggle_sync_d;
    wire       wr_frame_inc_rd;    // wr_frame_inc 脉冲, rd_clk 域

    // ---- CDC: adcclk → rd_clk (frame_depth_fifo) ----
    // 每项写入后稳定不变，3-stage sync
    reg  [31:0] frame_depth_fifo_sync [0:MAX_FRAMES-1][0:2];
    wire [31:0] frame_depth_fifo_rd [0:MAX_FRAMES-1];

    // ---- rd_clk 域: o_fifo_prelast + o_frame_num ----
    reg                        rst_n_rdclk;          // i_rst_n 同步到 rd_clk 域 (1 拍)
    reg  [31:0] rd_pixel_cnt;
    reg         prelast_reg;
    reg  [FRAME_NUM_W-1:0] frames_in_fifo;        // 可用帧计数: 有效帧写入DDR时+1, FX2读完一帧时-1
    reg  [BLOCK_ID_LOWER_W-1:0] rd_frame_idx;       // fifo 侧当前读出帧索引
    wire [31:0] rd_frame_depth_active;              // = frame_depth_fifo_rd[rd_frame_idx]

    // ==================================================================
    // 辅助信号-组合逻辑 (ui_clk 域)
    // ==================================================================
    wire frame_ended       = !frame_active_ui;
    wire axi_wr_idle_posedge = i_axi_wr_idle && !axi_wr_idle_d1;
    wire axi_rd_idle_posedge = i_axi_rd_idle && !axi_rd_idle_d1;
    wire wr_not_full;
    wire wr_burst_ready;
    wire wr_partial_ready;
    wire [BYTE_COUNT_W-1:0] wr_partial_bytes;
    wire [AXI_ADDR_WIDTH-1:0] wr_block_base;
    wire [AXI_ADDR_WIDTH-1:0] rd_block_base;
    wire [AXI_ADDR_WIDTH-1:0] rd_remaining;
    wire rd_has_full_burst;
    wire rd_has_data;
    wire rd_fifo_has_space_full;
    wire rd_fifo_has_space_partial;
    wire [BYTE_COUNT_W+3:0] rd_partial_units;

    assign wr_not_full = (ddr_wr_block_id[BLOCK_ID_LOWER_W-1:0] !=
                          ddr_rd_block_id[BLOCK_ID_LOWER_W-1:0]) ||
                         (ddr_wr_block_id[BLOCK_ID_W-1] ==
                          ddr_rd_block_id[BLOCK_ID_W-1]);

    assign wr_burst_ready   = (wrfifo_rdcnt >= BURST_UNITS);
    assign wr_partial_ready = frame_ended && !wrfifo_empty &&
                              (wrfifo_rdcnt < BURST_UNITS);
    assign wr_partial_bytes = wrfifo_rdcnt * AXI_DATA_BYTES;

    assign wr_block_base = ddr_wr_block_id[BLOCK_ID_LOWER_W-1:0] * MAX_FRAME_DEPTH_BYTES;
    assign rd_block_base = ddr_rd_block_id[BLOCK_ID_LOWER_W-1:0] * MAX_FRAME_DEPTH_BYTES;

    assign rd_remaining = ddr_block_end_ptr[ddr_rd_block_id[BLOCK_ID_LOWER_W-1:0]]
                          - (rd_block_base + ddr_rd_byte_count) + 1;
    assign rd_has_full_burst = (rd_remaining >= BURST_BYTES);
    assign rd_has_data       = (rd_remaining > 0);
    assign rd_fifo_has_space_full = (rdfifo_wrcnt < (FIFO_DEPTH - BURST_UNITS));
    assign rd_partial_units  = (rd_remaining + AXI_DATA_BYTES - 1) / AXI_DATA_BYTES;
    assign rd_fifo_has_space_partial = (rdfifo_wrcnt < (FIFO_DEPTH - rd_partial_units));

    // rd_frame_depth_active: 从 synced 数组按 rd_frame_idx 查表
    assign rd_frame_depth_active = frame_depth_fifo_rd[rd_frame_idx];

    // ==================================================================
    // ---- i_adcclk 域: 复位同步 (i_rst_n 同步到 adcclk) ----
    // ==================================================================
    always @(posedge i_adcclk) begin
        rst_n_adcclk <= i_rst_n;
    end

    // ==================================================================
    // ---- i_adcclk 域: 边沿检测 ----
    // ==================================================================
    always @(posedge i_adcclk) begin
        if (!rst_n_adcclk) begin
            frame_start_d <= 1'b0;
            frame_end_d   <= 1'b0;
        end else begin
            frame_start_d <= i_frame_start;
            frame_end_d   <= i_frame_end;
            frame_start_rise <= i_frame_start && !frame_start_d;
            frame_end_rise   <= i_frame_end   && !frame_end_d;
        end
    end

    // ==================================================================
    // ---- i_adcclk 域: frame_active + 像素计数器 + frame_valid ----
    // ==================================================================
    assign frame_depth_w = (i_read_mode == 2'd0) ?
        {16'd0, i_image_width} : (i_image_width * i_image_height);

    always @(posedge i_adcclk) begin
        if (!rst_n_adcclk) begin
            frame_active          <= 1'b0;
            pixel_cnt             <= 32'd0;
            frame_depth_reg       <= 32'd0;
            wr_frame_valid_adcclk <= 1'b0;
            depth_wr_ptr          <= 0;
        end else begin
            if (frame_start_rise) begin
                frame_active           <= 1'b1;
                frame_depth_reg        <= frame_depth_w;
                pixel_cnt              <= 32'd0;
                wr_frame_valid_adcclk  <= 1'b0;
            end

            if (frame_active && i_wr_en && i_pixel_type == 2'b10) begin
                pixel_cnt <= pixel_cnt + 1'b1;
            end

            if (frame_end_rise) begin
                frame_active <= 1'b0;
                if (pixel_cnt == frame_depth_reg) begin
                    wr_frame_valid_adcclk <= 1'b1;
                    // 记录该帧像素深度到 fifo（CDC 到 rd_clk）
                    frame_depth_fifo[depth_wr_ptr[BLOCK_ID_LOWER_W-1:0]] <= frame_depth_reg;
                    depth_wr_ptr <= depth_wr_ptr + 1'b1;
                end else begin
                    wr_frame_valid_adcclk <= 1'b0;
                end
            end
        end
    end

    // ==================================================================
    // ---- i_adcclk 域: wr-fifo 写 + o_frame_exception ----
    // ==================================================================
    assign wrfifo_wr_en = i_wr_en && (i_pixel_type == 2'b10) && frame_active;

    always @(posedge i_adcclk) begin
        if (!rst_n_adcclk) begin
            frame_exception_adcclk <= 1'b0;
        end else begin
            if (frame_end_rise && pixel_cnt != frame_depth_reg)
                frame_exception_adcclk <= 1'b1;
            else
                frame_exception_adcclk <= 1'b0;
        end
    end
    assign o_frame_exception = frame_exception_adcclk;

    // ==================================================================
    // ---- CDC: i_adcclk → i_ui_clk ----
    // ==================================================================

    // frame_active
    always @(posedge i_ui_clk) begin
        if (!i_rst_n) begin
            frame_active_sync <= 3'b000;
        end else begin
            frame_active_sync[0] <= frame_active;
            frame_active_sync[1] <= frame_active_sync[0];
        end
    end
    assign frame_active_ui = frame_active_sync[1];

    // frame_start_rise → 上升沿 → frame_start_rise_ui
    always @(posedge i_ui_clk) begin
        if (!i_rst_n) begin
            frame_start_sync   <= 3'b000;
            frame_start_sync_d <= 1'b0;
        end else begin
            frame_start_sync[0] <= frame_start_rise;
            frame_start_sync[1] <= frame_start_sync[0];
            frame_start_sync[2] <= frame_start_sync[1];
            frame_start_sync_d  <= frame_start_sync[2];
        end
    end
    assign frame_start_rise_ui = frame_start_sync[2] && !frame_start_sync_d;

    // wr_frame_valid
    always @(posedge i_ui_clk) begin
        if (!i_rst_n) wr_frame_valid_sync <= 3'b000;
        else begin
            wr_frame_valid_sync[0] <= wr_frame_valid_adcclk;
            wr_frame_valid_sync[1] <= wr_frame_valid_sync[0];
            wr_frame_valid_sync[2] <= wr_frame_valid_sync[1];
        end
    end

    // ==================================================================
    // ---- ui_clk 域: 写 FSM — 状态寄存器 ----
    // ==================================================================
    always @(posedge i_ui_clk) begin
        if (!i_rst_n)
            wr_state <= S_WR_IDLE;
        else
            wr_state <= wr_state_next;
    end

    // ==================================================================
    // ---- ui_clk 域: 写 FSM — 次态逻辑 ----
    // ==================================================================
    always @(*) begin
        wr_state_next = wr_state;
        case (wr_state)
            S_WR_IDLE: begin
                if (frame_start_rise_ui && wr_not_full)
                    wr_state_next = S_WR_WAIT;
            end
            S_WR_WAIT: begin
                if (i_axi_wr_idle) begin
                    if (wr_burst_ready || wr_partial_ready)
                        wr_state_next = S_WR_FIFO2AXI;
                    else if (frame_ended && wrfifo_empty)
                        wr_state_next = S_WR_IDLE;
                end
            end
            S_WR_FIFO2AXI: begin
                if (axi_wr_idle_posedge)
                    wr_state_next = S_WR_WAIT;
            end
            default: wr_state_next = S_WR_IDLE;
        endcase
    end

    // ==================================================================
    // ---- ui_clk 域: 写 FSM — 输出逻辑 ----
    // ==================================================================
    always @(posedge i_ui_clk) begin
        if (!i_rst_n) begin
            o_axi_wr_req           <= 1'b0;
            o_axi_wr_start_addr    <= 0;
            o_axi_wr_end_addr      <= 0;
            wr_burst_is_partial    <= 1'b0;
            wr_partial_bytes_latched <= 0;
            ddr_wr_byte_count      <= 0;
            ddr_wr_block_id        <= 0;
            ddr_block_end_ptr[0]   <= 0;
            ddr_block_end_ptr[1]   <= 0;
            ddr_block_end_ptr[2]   <= 0;
            ddr_block_end_ptr[3]   <= 0;
            ddr_block_end_ptr[4]   <= 0;
            ddr_block_end_ptr[5]   <= 0;
            ddr_block_end_ptr[6]   <= 0;
            ddr_block_end_ptr[7]   <= 0;
            wr_frame_inc          <= 1'b0;
        end else begin
            o_axi_wr_req      <= 1'b0;
            wr_frame_inc      <= 1'b0;

            case (wr_state)
                S_WR_IDLE: begin
                end

                S_WR_WAIT: begin
                    if (i_axi_wr_idle) begin
                        if (wr_burst_ready) begin
                            o_axi_wr_start_addr  <= wr_block_base + ddr_wr_byte_count;
                            o_axi_wr_end_addr    <= wr_block_base + ddr_wr_byte_count + BURST_BYTES;
                            o_axi_wr_req         <= 1'b1;
                            wr_burst_is_partial  <= 1'b0;
                        end else if (wr_partial_ready) begin
                            o_axi_wr_start_addr  <= wr_block_base + ddr_wr_byte_count;
                            o_axi_wr_end_addr    <= wr_block_base + ddr_wr_byte_count + wr_partial_bytes;
                            o_axi_wr_req         <= 1'b1;
                            wr_burst_is_partial  <= 1'b1;
                            wr_partial_bytes_latched <= wr_partial_bytes;
                        end else if (frame_ended && wrfifo_empty) begin
                            if (wr_frame_valid_sync[2]) begin
                                ddr_block_end_ptr[ddr_wr_block_id[BLOCK_ID_LOWER_W-1:0]]
                                    <= wr_block_base + ddr_wr_byte_count - 1;
                                ddr_wr_block_id   <= ddr_wr_block_id + 1;
                                wr_frame_inc      <= 1'b1;
                                ddr_wr_byte_count <= 0;
                            end else begin
                                ddr_wr_byte_count <= 0;
                            end
                        end
                    end
                end

                S_WR_FIFO2AXI: begin
                    if (axi_wr_idle_posedge) begin
                        if (wr_burst_is_partial)
                            ddr_wr_byte_count <= ddr_wr_byte_count + wr_partial_bytes_latched;
                        else
                            ddr_wr_byte_count <= ddr_wr_byte_count + BURST_BYTES;
                    end
                end

                default: ;
            endcase
        end
    end

    // ==================================================================
    // ---- ui_clk 域: 读 FSM — 状态寄存器 ----
    // ==================================================================
    always @(posedge i_ui_clk) begin
        if (!i_rst_n)
            rd_state <= S_RD_IDLE;
        else
            rd_state <= rd_state_next;
    end

    // ==================================================================
    // ---- ui_clk 域: 边沿检测寄存器 ----
    // ==================================================================
    always @(posedge i_ui_clk) begin
        if (!i_rst_n) begin
            axi_wr_idle_d1 <= 1'b0;
            axi_rd_idle_d1 <= 1'b0;
        end else begin
            axi_wr_idle_d1 <= i_axi_wr_idle;
            axi_rd_idle_d1 <= i_axi_rd_idle;
        end
    end

    // ==================================================================
    // ---- ui_clk 域: 读 FSM — 次态逻辑 ----
    // ==================================================================
    always @(*) begin
        rd_state_next = rd_state;
        case (rd_state)
            S_RD_IDLE: begin
                if (i_axi_rd_idle && (ddr_rd_block_id != ddr_wr_block_id)) begin
                    if ((rd_has_full_burst && rd_fifo_has_space_full) ||
                        (rd_has_data && !rd_has_full_burst && rd_fifo_has_space_partial))
                        rd_state_next = S_RD_AXI2FIFO;
                end
            end
            S_RD_AXI2FIFO: begin
                if (axi_rd_idle_posedge)
                    rd_state_next = S_RD_IDLE;
            end
            default: rd_state_next = S_RD_IDLE;
        endcase
    end

    // ==================================================================
    // ---- ui_clk 域: 读 FSM — 输出逻辑 ----
    // ==================================================================
    always @(posedge i_ui_clk) begin
        if (!i_rst_n) begin
            o_axi_rd_req         <= 1'b0;
            o_axi_rd_start_addr  <= 0;
            o_axi_rd_end_addr    <= 0;
            rd_frame_dec         <= 1'b0;
            ddr_rd_byte_count    <= 0;
            ddr_rd_block_id      <= 0;
        end else begin
            o_axi_rd_req <= 1'b0;
            rd_frame_dec <= 1'b0;

            case (rd_state)
                S_RD_IDLE: begin
                    if (i_axi_rd_idle && (ddr_rd_block_id != ddr_wr_block_id)) begin
                        if (rd_has_full_burst && rd_fifo_has_space_full) begin
                            o_axi_rd_start_addr <= rd_block_base + ddr_rd_byte_count;
                            o_axi_rd_end_addr   <= rd_block_base + ddr_rd_byte_count + BURST_BYTES;
                            o_axi_rd_req        <= 1'b1;
                        end else if (rd_has_data && !rd_has_full_burst
                                     && rd_fifo_has_space_partial) begin
                            o_axi_rd_start_addr <= rd_block_base + ddr_rd_byte_count;
                            o_axi_rd_end_addr   <= ddr_block_end_ptr[ddr_rd_block_id[BLOCK_ID_LOWER_W-1:0]] + 1;
                            o_axi_rd_req        <= 1'b1;
                        end
                    end
                end

                S_RD_AXI2FIFO: begin
                    if (axi_rd_idle_posedge) begin
                        if (rd_remaining <= BURST_BYTES) begin
                            ddr_rd_byte_count <= 0;
                            ddr_rd_block_id   <= ddr_rd_block_id + 1;
                            rd_frame_dec      <= 1'b1;
                        end else begin
                            ddr_rd_byte_count <= ddr_rd_byte_count + BURST_BYTES;
                        end
                    end
                end

                default: ;
            endcase
        end
    end

    // ==================================================================
    // ---- ui_clk 域: wr_frame_inc 脉冲 → toggle (CDC 到 rd_clk) ----
    // ==================================================================
    always @(posedge i_ui_clk) begin
        if (!i_rst_n)
            wr_frame_inc_toggle <= 1'b0;
        else if (wr_frame_inc)
            wr_frame_inc_toggle <= ~wr_frame_inc_toggle;
    end

    // ==================================================================
    // ---- i_rd_clk 域: 复位同步 (i_rst_n 同步到 rd_clk) ----
    // ==================================================================
    always @(posedge i_rd_clk) begin
        rst_n_rdclk <= i_rst_n;
    end

    // ==================================================================
    // ---- CDC: ui_clk → rd_clk (wr_frame_inc 脉冲, toggle 方式) ----
    // ==================================================================
    always @(posedge i_rd_clk) begin
        if (!rst_n_rdclk) begin
            wr_frame_inc_toggle_sync   <= 3'b000;
            wr_frame_inc_toggle_sync_d <= 1'b0;
        end else begin
            wr_frame_inc_toggle_sync[0] <= wr_frame_inc_toggle;
            wr_frame_inc_toggle_sync[1] <= wr_frame_inc_toggle_sync[0];
            wr_frame_inc_toggle_sync[2] <= wr_frame_inc_toggle_sync[1];
            wr_frame_inc_toggle_sync_d  <= wr_frame_inc_toggle_sync[2];
        end
    end
    assign wr_frame_inc_rd = wr_frame_inc_toggle_sync[2] ^ wr_frame_inc_toggle_sync_d;

    // ==================================================================
    // ---- CDC: adcclk → rd_clk (frame_depth_fifo 数组) ----
    //   每项在有效帧结束时写入后稳定不变，简单 3-stage sync 即可。
    // ==================================================================
    genvar gd;
    generate
        for (gd = 0; gd < MAX_FRAMES; gd = gd + 1) begin : gen_depth_sync
            always @(posedge i_rd_clk) begin
                if (!rst_n_rdclk) begin
                    frame_depth_fifo_sync[gd][0] <= 32'd0;
                    frame_depth_fifo_sync[gd][1] <= 32'd0;
                    frame_depth_fifo_sync[gd][2] <= 32'd0;
                end else begin
                    frame_depth_fifo_sync[gd][0] <= frame_depth_fifo[gd];
                    frame_depth_fifo_sync[gd][1] <= frame_depth_fifo_sync[gd][0];
                    frame_depth_fifo_sync[gd][2] <= frame_depth_fifo_sync[gd][1];
                end
            end
            assign frame_depth_fifo_rd[gd] = frame_depth_fifo_sync[gd][2];
        end
    endgenerate

    // ==================================================================
    // ---- i_rd_clk 域: o_fifo_prelast + o_frame_num + frames_in_fifo ----
    //   rd_frame_idx:           fifo 侧当前读出帧索引，读完一帧后 +1
    //   rd_frame_depth_active:  从 frame_depth_fifo_rd[rd_frame_idx] 查表
    //   frames_in_fifo:         可用帧计数, 有效帧写入DDR时+1, FX2读完一帧时-1
    // ==================================================================
    always @(posedge i_rd_clk) begin
        if (!rst_n_rdclk) begin
            rd_pixel_cnt  <= 32'd0;
            prelast_reg <= 1'b0;
            frames_in_fifo <= 0;
            rd_frame_idx  <= 0;
        end else begin
            // frames_in_fifo 计数: wr_frame_inc_rd 脉冲 +1, FX2 帧读完 -1
            // 带饱和度约束: 不超过 MAX_FRAMES, 不低于 0
            if (wr_frame_inc_rd && i_fifo_rd_en && (rd_pixel_cnt == rd_frame_depth_active-1))
                frames_in_fifo <= frames_in_fifo;       // 同时增减, 不变
            else if (wr_frame_inc_rd && frames_in_fifo < MAX_FRAMES)
                frames_in_fifo <= frames_in_fifo + 1'b1; // 有效帧写入 DDR (饱和)
            else if (i_fifo_rd_en && (rd_pixel_cnt == rd_frame_depth_active-1) && frames_in_fifo > 0)
                frames_in_fifo <= frames_in_fifo - 1'b1; // FX2 读完一帧 (防下溢)

            if (i_fifo_rd_en) begin
                if (rd_frame_depth_active == 0) begin
                    // 深度尚未 CDC 到达，保持等待
                    rd_pixel_cnt  <= 32'd0;
                    prelast_reg <= 1'b0;
                end else if (rd_pixel_cnt == rd_frame_depth_active - 2) begin
                    // 倒数第2字: 断言 prelast, 下一字为帧最后一字
                    prelast_reg <= 1'b1;
                    rd_pixel_cnt  <= rd_pixel_cnt + 1'b1;
                end else if (rd_pixel_cnt == rd_frame_depth_active-1) begin
                    // 帧读完: 推进 rd_frame_idx, 复位计数器
                    rd_frame_idx  <= rd_frame_idx + 1'b1;
                    rd_pixel_cnt  <= 32'd0;
                    prelast_reg <= 1'b0;
                end else begin
                    rd_pixel_cnt  <= rd_pixel_cnt + 1'b1;
                    prelast_reg <= 1'b0;
                end
            end else begin
                prelast_reg <= 1'b0;
            end
        end
    end

    assign o_fifo_prelast = prelast_reg;
    assign o_frame_num      = rdfifo_empty ? {FRAME_NUM_W{1'b0}} : frames_in_fifo;

    // ==================================================================
    // ---- 模块例化 ----
    // ==================================================================

    // ---- wr-fifo (16→128) ----
    // Xilinx FIFO 配置深度: 写侧512 / 读侧64
    // 实际可用深度:       写侧511 / 读侧63
    wr_ddr3_fifo u_wrfifo (
        .rst           (~i_rst_n),
        .wr_clk        (i_adcclk),
        .rd_clk        (i_ui_clk),
        .din           (i_wr_data),
        .wr_en         (wrfifo_wr_en),
        .rd_en         (i_wrfifo_rden),
        .dout          (o_wrfifo_dout),
        .full          (),
        .empty         (wrfifo_empty),
        .rd_data_count (wrfifo_rdcnt),
        .wr_data_count (),
        .wr_rst_busy   (),
        .rd_rst_busy   ()
    );

    // ---- rd-fifo (128→16) ----
    // Xilinx FIFO 配置深度: 写侧64 / 读侧512
    // 实际可用深度:       写侧63 / 读侧504
    assign o_fifo_data = rdfifo_dout;

    rd_ddr3_fifo u_rdfifo (
        .rst           (~i_rst_n),
        .wr_clk        (i_ui_clk),
        .rd_clk        (i_rd_clk),
        .din           (i_rdfifo_din),
        .wr_en         (i_rdfifo_wren),
        .rd_en         (i_fifo_rd_en),
        .dout          (rdfifo_dout),
        .full          (rdfifo_full),
        .empty         (rdfifo_empty),
        .rd_data_count (),
        .wr_data_count (rdfifo_wrcnt),
        .wr_rst_busy   (),
        .rd_rst_busy   ()
    );

endmodule

`timescale 1ns / 1ps
//==============================================================================
// Module : ccd_frame_buf
// Desc   : 乒乓帧缓存模块。
//          实例化两个 async_fifo 作为子 FIFO, 以帧为单位乒乓切换,
//          向上层呈现"深度为 2 的帧级 FIFO"。
//          包含 S0-S3 读写状态机 (读域 i_rd_clk 上升沿) + 每 FIFO 的帧状态机 (写域 i_adcclk 上升沿)。
//==============================================================================
module ccd_frame_buf #(
    parameter MAX_FRAME_DEPTH = 131072  // 子 FIFO 物理深度 (默认 2048×64)
) (
    // ---- 写侧 (ADCCLK 域) ----
    input  wire         i_adcclk,          // 写时钟 = ADCCLK (≤ 500kHz)
    input  wire         i_rst_n,           // 异步复位, 低有效
    input  wire [15:0]  i_wr_data,         // 像素数据 (来自 ccd_driver.o_pixel_data)
    input  wire         i_wr_en,           // 写使能 (来自 ccd_driver.o_data_valid)
    input  wire [1:0]   i_pixel_type,      // 像素类型 (00=bevel, 01=blank, 10=active)
    input  wire         i_frame_start,     // 标记新的一帧
    input  wire         i_frame_end,       // 标记帧的结束
    input  wire [31:0]  i_frame_depth,     // 运行时帧深度 (有效像素个数)

    // ---- 读侧 (FX2 域: i_rd_clk) ----
    input  wire         i_rd_clk,          // 读时钟 (FX2 Slave FIFO, ≤ 48MHz)
    output wire [15:0]  o_fifo_data,       // PP FIFO 读出数据 (16bit, 以帧为单位)
    output wire         o_fifo_empty,      // PP FIFO 空 (0 帧)
    output wire         o_fifo_half_full,  // PP FIFO 半满 (1 帧)
    output wire         o_fifo_full,       // PP FIFO 满 (2 帧)
    input  wire         i_fifo_rd_en,      // PP FIFO 读使能
    output wire         o_rd_fifo_sel,     // 当前读 FIFO 选择 (0=读fifo0, 1=读fifo1)
    output wire         o_fifo_last_word,  // 当前读出字是帧最后一字

    // ---- 异常帧 ----
    output wire         o_frame_exception  // 帧异常, 读到有效像素数不等于 i_frame_depth 的帧
);

    // ==================================================================
    // 状态编码
    // ==================================================================
    localparam FRAME_EMPTY     = 2'd0;
    localparam FRAME_READY     = 2'd1;
    localparam FRAME_EXCEPTION = 2'd2;

    localparam S_WR0_RD1 = 2'd0;  // S0: 写 fifo0, 读 fifo1
    localparam S_WR1_RD0 = 2'd1;  // S1: 写 fifo1, 读 fifo0
    localparam S_NW_RD1  = 2'd2;  // S2: 不写,   读 fifo1
    localparam S_NW_RD0  = 2'd3;  // S3: 不写,   读 fifo0

    // ==================================================================
    // 子 FIFO 信号
    // ==================================================================
    wire        fifo0_wr_en, fifo1_wr_en;
    wire        fifo0_rd_en, fifo1_rd_en;
    wire        fifo0_empty, fifo1_empty;
    wire        fifo0_full,  fifo1_full;
    wire        fifo0_almost_empty, fifo1_almost_empty;
    wire [15:0] fifo0_rd_data, fifo1_rd_data;

    // 子 FIFO 独立复位 (来自读域 S0-S3 自环复位请求)
    wire fifo0_rst_req;
    wire fifo1_rst_req;
    wire fifo0_rst_n = i_rst_n && !fifo0_rst_req;
    wire fifo1_rst_n = i_rst_n && !fifo1_rst_req;

    // ==================================================================
    // 子 FIFO 实例化
    // ==================================================================
    async_fifo #(
        .DATA_WIDTH(16),
        .FIFO_DEPTH(MAX_FRAME_DEPTH)
    ) u_fifo0 (
        .i_wr_clk      (i_adcclk),
        .i_rst_n       (fifo0_rst_n),
        .i_wr_data     (i_wr_data),
        .i_wr_en       (fifo0_wr_en),
        .o_full        (fifo0_full),
        .o_almost_full (),
        .i_rd_clk      (i_rd_clk),
        .o_rd_data     (fifo0_rd_data),
        .i_rd_en       (fifo0_rd_en),
        .o_empty       (fifo0_empty),
        .o_almost_empty(fifo0_almost_empty)
    );

    async_fifo #(
        .DATA_WIDTH(16),
        .FIFO_DEPTH(MAX_FRAME_DEPTH)
    ) u_fifo1 (
        .i_wr_clk      (i_adcclk),
        .i_rst_n       (fifo1_rst_n),
        .i_wr_data     (i_wr_data),
        .i_wr_en       (fifo1_wr_en),
        .o_full        (fifo1_full),
        .o_almost_full (),
        .i_rd_clk      (i_rd_clk),
        .o_rd_data     (fifo1_rd_data),
        .i_rd_en       (fifo1_rd_en),
        .o_empty       (fifo1_empty),
        .o_almost_empty(fifo1_almost_empty)
    );

    // ==================================================================
    // 写域 — 边沿检测 (i_adcclk 上升沿)
    // ==================================================================

    // frame_start 边沿检测
    reg frame_start_d;
    wire frame_start_rise;

    always @(posedge i_adcclk or negedge i_rst_n) begin
        if (!i_rst_n)
            frame_start_d <= 1'b0;
        else
            frame_start_d <= i_frame_start;
    end
    assign frame_start_rise = i_frame_start && !frame_start_d;

    // frame_end 边沿检测
    reg frame_end_d;
    wire frame_end_rise;
    wire frame_end_fall;

    always @(posedge i_adcclk or negedge i_rst_n) begin
        if (!i_rst_n)
            frame_end_d <= 1'b0;
        else
            frame_end_d <= i_frame_end;
    end
    assign frame_end_rise = i_frame_end && !frame_end_d;
    assign frame_end_fall = !i_frame_end && frame_end_d;

    // ==================================================================
    // CDC: 读域 → 写域 (wr_target, wr_enable, fifo_rst_req, exception)
    //   S0-S3 状态机在写域运行, 通过 wr_target/wr_enable 控制写行为。
    //   fifo_rst_req / rd_exception 为自环时的复位/异常脉冲。
    // ==================================================================
    wire wr_target;          // 读域 S0-S3: 0=写fifo0, 1=写fifo1
    wire wr_enable;          // 读域 S0-S3: 1=正在写 (S0/S1)
    wire fifo0_rst_req_rd;   // 读域 S0-S3: 自环时复位 fifo0
    wire fifo1_rst_req_rd;   // 读域 S0-S3: 自环时复位 fifo1
    wire rd_exception;       // 读域 S0-S3: 自环异常脉冲

    reg [1:0] wr_target_sync;
    reg [1:0] wr_enable_sync;
    reg [1:0] fifo0_rst_req_sync;
    reg [1:0] fifo1_rst_req_sync;
    reg [1:0] rd_exception_sync;

    always @(posedge i_adcclk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            wr_target_sync      <= 2'b00;
            wr_enable_sync      <= 2'b00;
            fifo0_rst_req_sync  <= 2'b00;
            fifo1_rst_req_sync  <= 2'b00;
            rd_exception_sync   <= 2'b00;
        end else begin
            wr_target_sync[0]     <= wr_target;
            wr_target_sync[1]     <= wr_target_sync[0];
            wr_enable_sync[0]     <= wr_enable;
            wr_enable_sync[1]     <= wr_enable_sync[0];
            fifo0_rst_req_sync[0] <= fifo0_rst_req_rd;
            fifo0_rst_req_sync[1] <= fifo0_rst_req_sync[0];
            fifo1_rst_req_sync[0] <= fifo1_rst_req_rd;
            fifo1_rst_req_sync[1] <= fifo1_rst_req_sync[0];
            rd_exception_sync[0]  <= rd_exception;
            rd_exception_sync[1]  <= rd_exception_sync[0];
        end
    end

    // 子 FIFO 独立复位 (来自读域 S0-S3 自环复位请求)
    assign fifo0_rst_req = fifo0_rst_req_sync[1];
    assign fifo1_rst_req = fifo1_rst_req_sync[1];

    // ==================================================================
    // 写域 — 帧深度锁存 + 像素计数器
    //   像素计数仅在 wr_enable_sync 有效时递增 (S0/S1 态),
    //   避免 S2/S3 等待态时误计入被丢弃帧的像素。
    // ==================================================================
    reg [31:0] frame_depth_latched;
    reg [31:0] pixel_cnt;

    always @(posedge i_adcclk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            frame_depth_latched <= 32'd0;
            pixel_cnt           <= 32'd0;
        end else begin
            // 帧开始时锁存帧深度, 复位像素计数器
            if (frame_start_rise) begin
                frame_depth_latched <= i_frame_depth;
                pixel_cnt           <= 32'd0;
            end else if (i_wr_en && i_pixel_type == 2'b10
                         && wr_enable_sync[1]) begin
                pixel_cnt <= pixel_cnt + 1'b1;
            end
        end
    end

    // ==================================================================
    // 写域 — fifo_empty CDC (读域 → 写域, 仅用于帧状态机)
    //   S0-S3 已迁至写域, 不再需要此 CDC; 帧状态机 READY→EMPTY
    //   过渡仍需读域 fifo_empty 上升沿检测。
    // ==================================================================
    reg [1:0] fifo0_empty_sync;
    reg [1:0] fifo1_empty_sync;
    reg       fifo0_empty_sync_prev;
    reg       fifo1_empty_sync_prev;
    wire      fifo0_empty_rise;  // 读空了 fifo0
    wire      fifo1_empty_rise;  // 读空了 fifo1

    always @(posedge i_adcclk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            fifo0_empty_sync       <= 2'b00;
            fifo1_empty_sync       <= 2'b00;
            fifo0_empty_sync_prev  <= 1'b1;
            fifo1_empty_sync_prev  <= 1'b1;
        end else begin
            // 双级同步 fifo_empty (读域 → 写域)
            fifo0_empty_sync[0] <= fifo0_empty;
            fifo0_empty_sync[1] <= fifo0_empty_sync[0];
            fifo1_empty_sync[0] <= fifo1_empty;
            fifo1_empty_sync[1] <= fifo1_empty_sync[0];
            // 上一拍值 (用于边沿检测)
            fifo0_empty_sync_prev <= fifo0_empty_sync[1];
            fifo1_empty_sync_prev <= fifo1_empty_sync[1];
        end
    end
    assign fifo0_empty_rise = fifo0_empty_sync[1] && !fifo0_empty_sync_prev;
    assign fifo1_empty_rise = fifo1_empty_sync[1] && !fifo1_empty_sync_prev;

    // ==================================================================
    // 写域 — 帧状态机 (每 FIFO 独立)
    //   EMPTY / READY / EXCEPTION
    //   使用 wr_enable_sync + wr_target_sync 替代原 state 信号:
    //     写 fifo0: wr_enable && !wr_target
    //     写 fifo1: wr_enable &&  wr_target
    // ==================================================================
    reg [1:0] fifo0_frame_state;
    reg [1:0] fifo1_frame_state;

    always @(posedge i_adcclk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            fifo0_frame_state <= FRAME_EMPTY;
            fifo1_frame_state <= FRAME_EMPTY;
        end else begin
            // ---- fifo0 帧状态 ----
            case (fifo0_frame_state)
                FRAME_EMPTY: begin
                    if (frame_end_rise && wr_enable_sync[1] && !wr_target_sync[1]) begin
                        if (pixel_cnt == frame_depth_latched)
                            fifo0_frame_state <= FRAME_READY;
                        else
                            fifo0_frame_state <= FRAME_EXCEPTION;
                    end
                end
                FRAME_READY: begin
                    if (fifo0_empty_rise)
                        fifo0_frame_state <= FRAME_EMPTY;
                end
                FRAME_EXCEPTION: begin
                    if (frame_end_fall)
                        fifo0_frame_state <= FRAME_EMPTY;
                end
                default: fifo0_frame_state <= FRAME_EMPTY;
            endcase

            // ---- fifo1 帧状态 ----
            case (fifo1_frame_state)
                FRAME_EMPTY: begin
                    if (frame_end_rise && wr_enable_sync[1] && wr_target_sync[1]) begin
                        if (pixel_cnt == frame_depth_latched)
                            fifo1_frame_state <= FRAME_READY;
                        else
                            fifo1_frame_state <= FRAME_EXCEPTION;
                    end
                end
                FRAME_READY: begin
                    if (fifo1_empty_rise)
                        fifo1_frame_state <= FRAME_EMPTY;
                end
                FRAME_EXCEPTION: begin
                    if (frame_end_fall)
                        fifo1_frame_state <= FRAME_EMPTY;
                end
                default: fifo1_frame_state <= FRAME_EMPTY;
            endcase
        end
    end

    wire fifo0_frame_ready = (fifo0_frame_state == FRAME_READY);
    wire fifo1_frame_ready = (fifo1_frame_state == FRAME_READY);

    // ==================================================================
    // 写域 — 写使能路由
    //   使用 CDC 同步后的 wr_enable_sync / wr_target_sync 控制。
    // ==================================================================
    wire wr_active = i_wr_en && (i_pixel_type == 2'b10);

    assign fifo0_wr_en = (wr_target_sync[1] == 1'b0) && wr_enable_sync[1] && wr_active;
    assign fifo1_wr_en = (wr_target_sync[1] == 1'b1) && wr_enable_sync[1] && wr_active;

    // ==================================================================
    // 写域 — o_frame_exception 输出
    //   两个来源: (1) 帧状态机检测到帧长度异常 (写域原生)
    //            (2) S0-S3 自环时的异常脉冲 (读域 CDC 过来)
    // ==================================================================
    reg [1:0] fifo0_frame_state_prev;
    reg [1:0] fifo1_frame_state_prev;
    wire       fifo0_exception_rise;
    wire       fifo1_exception_rise;

    always @(posedge i_adcclk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            fifo0_frame_state_prev <= FRAME_EMPTY;
            fifo1_frame_state_prev <= FRAME_EMPTY;
        end else begin
            fifo0_frame_state_prev <= fifo0_frame_state;
            fifo1_frame_state_prev <= fifo1_frame_state;
        end
    end
    assign fifo0_exception_rise = (fifo0_frame_state == FRAME_EXCEPTION) &&
                                   (fifo0_frame_state_prev != FRAME_EXCEPTION);
    assign fifo1_exception_rise = (fifo1_frame_state == FRAME_EXCEPTION) &&
                                   (fifo1_frame_state_prev != FRAME_EXCEPTION);

    assign o_frame_exception = fifo0_exception_rise || fifo1_exception_rise ||
                                rd_exception_sync[1];

    // ==================================================================
    // CDC: 写域 → 读域
    //   - frame_end, frame_start: 帧边界标记 (用于读域 S0-S3 状态机)
    //   - fifo0_frame_ready, fifo1_frame_ready: 帧就绪标志 (用于读域状态机 + 输出标志)
    // ==================================================================

    // ---- frame_end CDC (写域 → 读域) ----
    //   使用 3 级同步 + 寄存器边沿检测, 确保 frame_end_fall_rd
    //   在 fifo_ready_sync[2] 稳定后才触发 (避免同沿竞争)。
    reg [2:0] frame_end_rd_sync;
    reg       frame_end_rd_sync_prev;
    reg       frame_end_rise_rd;
    reg       frame_end_fall_rd;

    always @(posedge i_rd_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            frame_end_rd_sync       <= 3'b000;
            frame_end_rd_sync_prev  <= 1'b0;
            frame_end_rise_rd       <= 1'b0;
            frame_end_fall_rd       <= 1'b0;
        end else begin
            frame_end_rd_sync[0] <= i_frame_end;
            frame_end_rd_sync[1] <= frame_end_rd_sync[0];
            frame_end_rd_sync[2] <= frame_end_rd_sync[1];
            frame_end_rd_sync_prev <= frame_end_rd_sync[2];
            // 寄存器边沿检测 (比 fifo_ready_sync[2] 晚 1 rd_clk, 消除竞争)
            frame_end_rise_rd <= frame_end_rd_sync[2] && !frame_end_rd_sync_prev;
            frame_end_fall_rd <= !frame_end_rd_sync[2] && frame_end_rd_sync_prev;
        end
    end

    // ---- frame_start CDC (写域 → 读域) ----
    reg [1:0] frame_start_rd_sync;
    reg       frame_start_rd_d;
    wire      frame_start_rise_rd;

    always @(posedge i_rd_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            frame_start_rd_sync <= 2'b00;
            frame_start_rd_d    <= 1'b0;
        end else begin
            frame_start_rd_sync[0] <= i_frame_start;
            frame_start_rd_sync[1] <= frame_start_rd_sync[0];
            frame_start_rd_d       <= frame_start_rd_sync[1];
        end
    end
    assign frame_start_rise_rd = frame_start_rd_sync[1] && !frame_start_rd_d;

    // ---- fifoX_frame_ready CDC (写域 → 读域) ----
    //   使用 3 级同步器 + 边沿检测, 确保在 frame_end_fall_rd
    //   触发时 fifo_ready_sync 已稳定 (避免同一个 rd_clk 沿的竞争)。
    reg [2:0] fifo0_ready_sync;
    reg [2:0] fifo1_ready_sync;
    reg       fifo0_ready_sync_prev;
    reg       fifo1_ready_sync_prev;
    wire      fifo0_ready_rise;
    wire      fifo1_ready_rise;

    always @(posedge i_rd_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            fifo0_ready_sync       <= 3'b000;
            fifo1_ready_sync       <= 3'b000;
            fifo0_ready_sync_prev  <= 1'b0;
            fifo1_ready_sync_prev  <= 1'b0;
        end else begin
            fifo0_ready_sync[0] <= fifo0_frame_ready;
            fifo0_ready_sync[1] <= fifo0_ready_sync[0];
            fifo0_ready_sync[2] <= fifo0_ready_sync[1];
            fifo1_ready_sync[0] <= fifo1_frame_ready;
            fifo1_ready_sync[1] <= fifo1_ready_sync[0];
            fifo1_ready_sync[2] <= fifo1_ready_sync[1];

            fifo0_ready_sync_prev <= fifo0_ready_sync[2];
            fifo1_ready_sync_prev <= fifo1_ready_sync[2];
        end
    end
    assign fifo0_ready_rise = fifo0_ready_sync[2] && !fifo0_ready_sync_prev;
    assign fifo1_ready_rise = fifo1_ready_sync[2] && !fifo1_ready_sync_prev;

    // ==================================================================
    // 读域 — S0-S3 读写状态机 (i_rd_clk 上升沿)
    //
    //   async_fifo 已在上升沿更新 o_empty / o_rd_data, 本状态机
    //   同样在上升沿采样 fifo_empty 和更新 rd_sel, 与 async_fifo
    //   的输出寄存器处于同一个时钟沿, 无跨沿时序问题。
    //   fifo_frame_ready 通过 3 级同步器从写域获取。
    //   自环条件在 frame_end_fall_rd 时评估；跨状态转移
    //   (S0→S2 / S1→S3) 不受 frame_end 限制, 任何时刻满足即触发。
    //
    //   输出:
    //     wr_target : 0=写fifo0, 1=写fifo1  → CDC 到写域
    //     wr_enable : 1=正在写 (S0/S1)      → CDC 到写域
    //     rd_sel    : 0=读fifo0, 1=读fifo1  → 读域本地使用
    //     fifoX_rst_req_rd : 自环时复位子 FIFO → CDC 到写域
    //     rd_exception     : 自环异常脉冲     → CDC 到写域
    // ==================================================================
    reg [1:0] rd_state;
    reg       rd_exception_reg;
    reg       fifo0_rst_req_rd_reg;
    reg       fifo1_rst_req_rd_reg;

    always @(posedge i_rd_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            rd_state              <= S_WR0_RD1;
            rd_exception_reg      <= 1'b0;
            fifo0_rst_req_rd_reg  <= 1'b0;
            fifo1_rst_req_rd_reg  <= 1'b0;
        end else begin
            // 默认: 脉冲信号自动清零
            rd_exception_reg      <= 1'b0;
            fifo0_rst_req_rd_reg  <= 1'b0;
            fifo1_rst_req_rd_reg  <= 1'b0;

            case (rd_state)
                // ----------------------------------------------------------
                // S0: 写 fifo0, 读 fifo1
                // ----------------------------------------------------------
                S_WR0_RD1: begin
                    // 跨状态: fifo0 写完了但 fifo1 还没读空 → 暂停写入
                    if (fifo0_ready_sync[2] && !fifo1_empty) begin
                        rd_state <= S_NW_RD1;
                    end
                    // frame_end 下降沿: 评估自环 vs 正常切换
                    else if (frame_end_fall_rd) begin
                        if (!fifo1_empty || !fifo0_ready_sync[2]) begin
                            // 自环: 读侧忙 或 写侧帧异常 → 复位 fifo0
                            rd_state <= S_WR0_RD1;
                            fifo0_rst_req_rd_reg <= 1'b1;
                            rd_exception_reg <= 1'b1;
                        end else begin
                            // → S1: 正常乒乓切换
                            rd_state <= S_WR1_RD0;
                        end
                    end
                end

                // ----------------------------------------------------------
                // S1: 写 fifo1, 读 fifo0
                // ----------------------------------------------------------
                S_WR1_RD0: begin
                    // 跨状态: fifo1 写完了但 fifo0 还没读空 → 暂停写入
                    if (fifo1_ready_sync[2] && !fifo0_empty) begin
                        rd_state <= S_NW_RD0;
                    end
                    // frame_end 下降沿: 评估自环 vs 正常切换
                    else if (frame_end_fall_rd) begin
                        if (!fifo0_empty || !fifo1_ready_sync[2]) begin
                            // 自环: 读侧忙 或 写侧帧异常 → 复位 fifo1
                            rd_state <= S_WR1_RD0;
                            fifo1_rst_req_rd_reg <= 1'b1;
                            rd_exception_reg <= 1'b1;
                        end else begin
                            // → S0: 正常乒乓切换
                            rd_state <= S_WR0_RD1;
                        end
                    end
                end

                // ----------------------------------------------------------
                // S2: 不写, 读 fifo1 (等待 fifo1 被清空)
                // ----------------------------------------------------------
                S_NW_RD1: begin
                    if (fifo1_empty)
                        rd_state <= S_WR1_RD0;
                end

                // ----------------------------------------------------------
                // S3: 不写, 读 fifo0 (等待 fifo0 被清空)
                // ----------------------------------------------------------
                S_NW_RD0: begin
                    if (fifo0_empty)
                        rd_state <= S_WR0_RD1;
                end

                default: rd_state <= S_WR0_RD1;
            endcase
        end
    end

    // ---- S0-S3 输出 ----
    wire rd_sel;
    assign wr_target         = (rd_state == S_WR1_RD0 || rd_state == S_NW_RD0);
    assign wr_enable         = (rd_state == S_WR0_RD1 || rd_state == S_WR1_RD0);
    assign rd_sel            = ~wr_target; // 0=读fifo0, 1=读fifo1
    assign fifo0_rst_req_rd  = fifo0_rst_req_rd_reg;
    assign fifo1_rst_req_rd  = fifo1_rst_req_rd_reg;
    assign rd_exception      = rd_exception_reg;

    // ==================================================================
    // 读域 — 子 FIFO empty 边沿检测 (帧已被完全读出)
    // ==================================================================
    reg fifo0_empty_rd_d;
    reg fifo1_empty_rd_d;
    wire fifo0_empty_rd_rise;
    wire fifo1_empty_rd_rise;

    always @(posedge i_rd_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            fifo0_empty_rd_d <= 1'b1;
            fifo1_empty_rd_d <= 1'b1;
        end else begin
            fifo0_empty_rd_d <= fifo0_empty;
            fifo1_empty_rd_d <= fifo1_empty;
        end
    end
    assign fifo0_empty_rd_rise = fifo0_empty && !fifo0_empty_rd_d;
    assign fifo1_empty_rd_rise = fifo1_empty && !fifo1_empty_rd_d;

    // ==================================================================
    // 读域 — 就绪帧计数器 (上升沿更新)
    //   统计当前有几个子 FIFO 持有就绪帧。
    //   先用组合逻辑计算次态, 再在时序块中赋值,
    //   避免同一 always 块中多个 NBA 覆盖问题。
    // ==================================================================
    reg [1:0] frames_ready_cnt;

    reg [1:0] frames_ready_cnt_next;
    always @(*) begin
        frames_ready_cnt_next = frames_ready_cnt;
        // 帧就绪: +1
        if (fifo0_ready_rise) frames_ready_cnt_next = frames_ready_cnt_next + 1'b1;
        if (fifo1_ready_rise) frames_ready_cnt_next = frames_ready_cnt_next + 1'b1;
        // 帧读空: -1
        if (fifo0_empty_rd_rise) frames_ready_cnt_next = frames_ready_cnt_next - 1'b1;
        if (fifo1_empty_rd_rise) frames_ready_cnt_next = frames_ready_cnt_next - 1'b1;
    end

    always @(posedge i_rd_clk or negedge i_rst_n) begin
        if (!i_rst_n)
            frames_ready_cnt <= 2'd0;
        else
            frames_ready_cnt <= frames_ready_cnt_next;
    end

    // ==================================================================
    // 读域 — 读使能路由 + 数据 MUX
    //   rd_sel = ~wr_target, 由读域 S0-S3 状态机直接产生:
    //   S1/S3 (wr_target=1) → rd_sel=0 → 读fifo0,
    //   S0/S2 (wr_target=0) → rd_sel=1 → 读fifo1。
    // ==================================================================
    assign fifo0_rd_en = i_fifo_rd_en && (rd_sel == 1'b0);
    assign fifo1_rd_en = i_fifo_rd_en && (rd_sel == 1'b1);

    // o_fifo_last_word — 组合 MUX 自 async_fifo 的输出寄存器
    // (async_fifo 已在上升沿更新 o_almost_empty, 此处无需再加一级)
    assign o_fifo_data      = (rd_sel == 1'b0) ? fifo0_rd_data      : fifo1_rd_data;
    assign o_fifo_last_word = (rd_sel == 1'b0) ? fifo0_almost_empty : fifo1_almost_empty;

    // ==================================================================
    // 读域 — PP FIFO 标志输出 (上升沿更新)
    // ==================================================================
    reg empty_reg;
    reg half_full_reg;
    reg full_reg;

    always @(posedge i_rd_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            empty_reg     <= 1'b1;
            half_full_reg <= 1'b0;
            full_reg      <= 1'b0;
        end else begin
            empty_reg     <= (frames_ready_cnt == 2'd0);
            half_full_reg <= (frames_ready_cnt == 2'd1);
            full_reg      <= (frames_ready_cnt == 2'd2);
        end
    end

    reg rd_sel_reg;
    always @(posedge i_rd_clk or negedge i_rst_n) begin
        if (!i_rst_n)
            rd_sel_reg <= 1'b0;
        else
            rd_sel_reg <= rd_sel;
    end

    assign o_fifo_empty     = empty_reg;
    assign o_fifo_half_full = half_full_reg;
    assign o_fifo_full      = full_reg;
    assign o_rd_fifo_sel    = rd_sel_reg;

endmodule

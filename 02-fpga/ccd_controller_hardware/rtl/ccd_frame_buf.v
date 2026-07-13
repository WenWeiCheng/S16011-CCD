`timescale 1ns / 1ps
//==============================================================================
// Module : ccd_frame_buf
// Desc   : 乒乓帧缓存模块。
//          实例化两个 async_fifo 作为子 FIFO, 以帧为单位乒乓切换,
//          向上层呈现"深度为 2 的帧级 FIFO"。
//          包含 S0-S3 读写状态机 (写域) + 每 FIFO 的帧状态机 (empty/ready/exception)。
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
    output wire         o_rd_fifo_sel,     // 当前读 FIFO 选择 (0=读fifo1, 1=读fifo0)

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
    wire [15:0] fifo0_rd_data, fifo1_rd_data;

    // 子 FIFO 独立复位 (写域自环时复位当前写 FIFO)
    wire        fifo0_rst_n = i_rst_n && !fifo0_rst_req;
    wire        fifo1_rst_n = i_rst_n && !fifo1_rst_req;

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
        .o_valid       ()
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
        .o_valid       ()
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
    // 写域 — 帧深度锁存 + 像素计数器
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
                         && (state == S_WR0_RD1 || state == S_WR1_RD0)) begin
                pixel_cnt <= pixel_cnt + 1'b1;
            end
        end
    end

    // ==================================================================
    // 写域 — 帧状态机 (每 FIFO 独立)
    //   EMPTY / READY / EXCEPTION
    // ==================================================================
    reg [1:0] fifo0_frame_state;
    reg [1:0] fifo1_frame_state;

    // 从读域同步来的 fifo_empty 标志
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

    always @(posedge i_adcclk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            fifo0_frame_state <= FRAME_EMPTY;
            fifo1_frame_state <= FRAME_EMPTY;
        end else begin
            // ---- fifo0 帧状态 ----
            case (fifo0_frame_state)
                FRAME_EMPTY: begin
                    // 仅在 S0 (写fifo0) 时, frame_end↑ 评估帧完成
                    if (frame_end_rise && state == S_WR0_RD1) begin
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
                    // 仅在 S1 (写fifo1) 时, frame_end↑ 评估帧完成
                    if (frame_end_rise && state == S_WR1_RD0) begin
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
    // 写域 — S0-S3 读写状态机 (i_adcclk 上升沿)
    //
    //   自环条件在 frame_end_fall 时评估；跨状态转移
    //   (S0→S2 / S1→S3) 不受 frame_end 限制, 任何时刻满足即触发。
    // ==================================================================
    reg [1:0] state;
    reg       frame_exception_reg;
    reg       fifo0_rst_req, fifo1_rst_req;

    always @(posedge i_adcclk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            state                 <= S_WR0_RD1;
            frame_exception_reg   <= 1'b0;
            fifo0_rst_req         <= 1'b0;
            fifo1_rst_req         <= 1'b0;
        end else begin
            // 默认: 脉冲信号自动清零
            frame_exception_reg <= 1'b0;
            fifo0_rst_req       <= 1'b0;
            fifo1_rst_req       <= 1'b0;

            case (state)
                // ----------------------------------------------------------
                // S0: 写 fifo0, 读 fifo1
                // ----------------------------------------------------------
                S_WR0_RD1: begin
                    // 跨状态: fifo0 写完了但 fifo1 还没读空 → 暂停写入
                    if (fifo0_frame_ready && !fifo1_empty_sync[1]) begin
                        state <= S_NW_RD1;
                    end
                    // frame_end 下降沿: 评估自环 vs 正常切换
                    else if (frame_end_fall) begin
                        if (!fifo1_empty_sync[1] || !fifo0_frame_ready) begin
                            // 自环: 读侧忙 或 写侧帧异常 → 复位 fifo0
                            state <= S_WR0_RD1;
                            fifo0_rst_req <= 1'b1;
                            frame_exception_reg <= 1'b1;
                        end else begin
                            // → S1: 正常乒乓切换
                            state <= S_WR1_RD0;
                        end
                    end
                end

                // ----------------------------------------------------------
                // S1: 写 fifo1, 读 fifo0
                // ----------------------------------------------------------
                S_WR1_RD0: begin
                    // 跨状态: fifo1 写完了但 fifo0 还没读空 → 暂停写入
                    if (fifo1_frame_ready && !fifo0_empty_sync[1]) begin
                        state <= S_NW_RD0;
                    end
                    // frame_end 下降沿: 评估自环 vs 正常切换
                    else if (frame_end_fall) begin
                        if (!fifo0_empty_sync[1] || !fifo1_frame_ready) begin
                            // 自环: 读侧忙 或 写侧帧异常 → 复位 fifo1
                            state <= S_WR1_RD0;
                            fifo1_rst_req <= 1'b1;
                            frame_exception_reg <= 1'b1;
                        end else begin
                            // → S0: 正常乒乓切换
                            state <= S_WR0_RD1;
                        end
                    end
                end

                // ----------------------------------------------------------
                // S2: 不写, 读 fifo1 (等待 fifo1 被清空)
                // ----------------------------------------------------------
                S_NW_RD1: begin
                    if (fifo1_empty_sync[1])
                        state <= S_WR1_RD0;
                end

                // ----------------------------------------------------------
                // S3: 不写, 读 fifo0 (等待 fifo0 被清空)
                // ----------------------------------------------------------
                S_NW_RD0: begin
                    if (fifo0_empty_sync[1])
                        state <= S_WR0_RD1;
                end

                default: state <= S_WR0_RD1;
            endcase
        end
    end

    // ==================================================================
    // 写域 — 写使能路由
    // ==================================================================
    // 使用组合逻辑路由, 避免 NBA 时序问题
    wire wr_active = i_wr_en && (i_pixel_type == 2'b10);

    assign fifo0_wr_en = (state == S_WR0_RD1) && wr_active;
    assign fifo1_wr_en = (state == S_WR1_RD0) && wr_active;

    // ==================================================================
    // 写域 — o_frame_exception 输出 (写域脉冲)
    // ==================================================================
    assign o_frame_exception = frame_exception_reg;

    // ==================================================================
    // CDC: 写域 → 读域
    //   - wr_rd_sel: 读选择信号 (0=读fifo1, 1=读fifo0)
    //   - fifo0_frame_ready, fifo1_frame_ready: 帧就绪标志
    // ==================================================================

    // 读选择: S0/S2 → 读 fifo1 (0), S1/S3 → 读 fifo0 (1)
    wire wr_rd_sel = (state == S_WR1_RD0 || state == S_NW_RD0);

    // 双级同步 wr_rd_sel → 读域
    reg [1:0] rd_sel_sync;
    always @(posedge i_rd_clk or negedge i_rst_n) begin
        if (!i_rst_n)
            rd_sel_sync <= 2'b00;
        else begin
            rd_sel_sync[0] <= wr_rd_sel;
            rd_sel_sync[1] <= rd_sel_sync[0];
        end
    end

    // 双级同步 fifoX_frame_ready → 读域 (用于输出标志)
    reg [1:0] fifo0_ready_sync;
    reg [1:0] fifo1_ready_sync;
    reg       fifo0_ready_sync_prev;
    reg       fifo1_ready_sync_prev;
    wire      fifo0_ready_rise;
    wire      fifo1_ready_rise;

    always @(posedge i_rd_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            fifo0_ready_sync       <= 2'b00;
            fifo1_ready_sync       <= 2'b00;
            fifo0_ready_sync_prev  <= 1'b0;
            fifo1_ready_sync_prev  <= 1'b0;
        end else begin
            fifo0_ready_sync[0] <= fifo0_frame_ready;
            fifo0_ready_sync[1] <= fifo0_ready_sync[0];
            fifo1_ready_sync[0] <= fifo1_frame_ready;
            fifo1_ready_sync[1] <= fifo1_ready_sync[0];

            fifo0_ready_sync_prev <= fifo0_ready_sync[1];
            fifo1_ready_sync_prev <= fifo1_ready_sync[1];
        end
    end
    assign fifo0_ready_rise = fifo0_ready_sync[1] && !fifo0_ready_sync_prev;
    assign fifo1_ready_rise = fifo1_ready_sync[1] && !fifo1_ready_sync_prev;

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
    // ==================================================================
    wire rd_sel = rd_sel_sync[1];  // 0=读fifo1, 1=读fifo0

    assign fifo0_rd_en = i_fifo_rd_en && (rd_sel == 1'b1);
    assign fifo1_rd_en = i_fifo_rd_en && (rd_sel == 1'b0);

    assign o_fifo_data = (rd_sel == 1'b1) ? fifo0_rd_data : fifo1_rd_data;

    // ==================================================================
    // 读域 — PP FIFO 标志输出 (下降沿更新)
    // ==================================================================
    reg empty_reg;
    reg half_full_reg;
    reg full_reg;
    reg rd_sel_reg;       // 当前读 FIFO 选择 (0=读fifo1, 1=读fifo0)

    always @(negedge i_rd_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            empty_reg     <= 1'b1;
            half_full_reg <= 1'b0;
            full_reg      <= 1'b0;
            rd_sel_reg    <= 1'b0;     // 复位默认读 fifo1 (S0 初始态)
        end else begin
            empty_reg     <= (frames_ready_cnt == 2'd0);
            half_full_reg <= (frames_ready_cnt == 2'd1);
            full_reg      <= (frames_ready_cnt == 2'd2);
            rd_sel_reg    <= rd_sel;   // rd_sel 已由 rd_sel_sync[1] 同步到读域
        end
    end

    assign o_fifo_empty     = empty_reg;
    assign o_fifo_half_full = half_full_reg;
    assign o_fifo_full      = full_reg;
    assign o_rd_fifo_sel    = rd_sel_reg;

endmodule

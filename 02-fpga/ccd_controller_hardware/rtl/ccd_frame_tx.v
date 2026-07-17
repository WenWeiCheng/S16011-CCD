`timescale 1ns / 1ps
//==============================================================================
// Module : ccd_frame_tx
// Desc   : 帧发送模块。从 ccd_frame_buf 读取帧数据,
//          发送至 EZ-USB Slave FIFO。
//          包含 idle / wait / transmit 三态状态机。
//          通过 i_frame_fifo_num 判断 PP FIFO 是否有数据可读。
//
//  状态转换:
//    idle    → wait   : i_frame_start 下降沿
//    wait    → transmit: PP FIFO 非空 && Slave FIFO 未满
//    transmit → idle   : fifo_last_pipe=1 (当前字是帧最后一字)
//
//  发送时序:
//    - o_frame_fifo_rd_en 在 i_ext_clk 上升沿拉高, 从 PP FIFO 读一字
//    - o_slave_fifo_data / o_slave_fifo_data_valid_n 在 i_ext_clk_n 上升沿更新
//    - o_frame_done_n 在 i_ext_clk_n 上升沿拉低, 同时 o_slave_fifo_data_valid_n=0,
//      EZ-USB Slave FIFO 在上升沿打包将数据发送给主机
//==============================================================================
module ccd_frame_tx #(
    parameter MAX_FRAMES = 2  // 最大缓存帧数 (需与 ccd_frame_buf 一致)
) (
    // 系统接口
    input  wire         i_ext_clk,            // 读时钟 (FX2 侧时钟)
    input  wire         i_ext_clk_n,          // i_ext_clk 的反相
    input  wire         i_rst_n,              // 异步复位, 低有效

    // PP FIFO 读接口, 以帧为单位, 宽度为 16bit
    input  wire [15:0]                i_frame_fifo_data,
    input  wire [$clog2(MAX_FRAMES+1)-1:0] i_frame_fifo_num,
    input  wire         i_frame_fifo_last_word,  // 当前读出字是帧最后一字 (来自 ccd_frame_buf.o_fifo_last_word)
    output wire         o_frame_fifo_rd_en,

    // FX2 Slave FIFO 接口
    output wire [15:0]  o_slave_fifo_data,
    output wire         o_slave_fifo_data_valid_n,
    input  wire         i_slave_fifo_empty_n,     // FX2 侧 FIFO 空反馈, 低有效
    input  wire         i_slave_fifo_full_n,     // FX2 侧 FIFO 满反馈, 低有效

    // 帧控制
    input  wire         i_frame_start,     // 开始一帧数据传输
    output wire         o_frame_done_n      // 一帧发送已完成, 低有效
);

    // ==================================================================
    // 状态编码
    // ==================================================================
    localparam S_IDLE     = 2'd0;
    localparam S_WAIT     = 2'd1;
    localparam S_TRANSMIT = 2'd2;

    // ==================================================================
    // 状态寄存器
    // ==================================================================
    reg [1:0] state;
    reg [1:0] state_next;

    // ==================================================================
    // 边沿检测 — i_frame_start 下降沿
    // ==================================================================
    reg frame_start_d;
    wire frame_start_fall;
    reg rd_en_reg;
    reg rd_en_was_active;
    reg [15:0] fifo_pipe_data;
    reg        fifo_pipe_valid;
    reg        fifo_last_pipe;
    reg [15:0] slave_data_reg;
    reg        slave_valid_n_reg;
    reg        frame_done_n_reg;

    always @(posedge i_ext_clk or negedge i_rst_n) begin
        if (!i_rst_n)
            frame_start_d <= 1'b0;
        else
            frame_start_d <= i_frame_start;
    end
    assign frame_start_fall = !i_frame_start && frame_start_d;

    // ==================================================================
    //  读使能 (i_ext_clk 上升沿寄存器输出)
    //   在 transmit 状态且 Slave FIFO 未满时拉高。
    //   用 state_next != S_IDLE 额外门控, 确保最后一字读出后立即停止,
    //   避免过渡周期仍拉高 rd_en 导致提前读出下一帧的首字。
    // ==================================================================

    always @(posedge i_ext_clk or negedge i_rst_n) begin
        if (!i_rst_n)
            rd_en_reg <= 1'b0;
        else
            rd_en_reg <= (state == S_TRANSMIT) && i_slave_fifo_full_n
                         && (state_next != S_IDLE) && !i_frame_fifo_last_word;
    end
    assign o_frame_fifo_rd_en = rd_en_reg;

    always @(posedge i_ext_clk or negedge i_rst_n) begin
        if (!i_rst_n)
            rd_en_was_active <= 1'b0;
        else
            rd_en_was_active <= rd_en_reg;
    end

    // ==================================================================
    // 次态组合逻辑
    // ==================================================================
    always @(*) begin
        state_next = state;
        case (state)
            S_IDLE: begin
                if (frame_start_fall)
                    state_next = S_WAIT;
            end

            S_WAIT: begin
                if ((i_frame_fifo_num != 0) && i_slave_fifo_full_n)
                    state_next = S_TRANSMIT;
            end

            S_TRANSMIT: begin
                // fifo_last_pipe=1 说明当前管道中的字是帧最后一字
                if (fifo_last_pipe)
                    state_next = S_IDLE;
            end

            default: state_next = S_IDLE;
        endcase
    end

    // ==================================================================
    // 状态更新 (i_ext_clk 上升沿)
    // ==================================================================
    always @(posedge i_ext_clk or negedge i_rst_n) begin
        if (!i_rst_n)
            state <= S_IDLE;
        else
            state <= state_next;
    end

    // ==================================================================
    // 数据管道 (i_ext_clk 上升沿采样)
    //
    //   async_fifo 在 i_ext_clk 上升沿更新 o_rd_data (与 rd_en_reg 同一时钟沿),
    //   同时 i_frame_fifo_data 已稳定, 在此采样并寄存。
    //   下一拍由 i_ext_clk_n 上升沿输出到 Slave FIFO。
    //
    //   管道有效标记:
    //     state→TRANSMIT 的下一拍 async_fifo 开始读出数据,
    //     数据在再下一拍的 posedge 稳定就绪。
    //     rd_en_was_active 在 i_ext_clk 上升沿记录"上一拍是否已处于 transmit 状态",
    //     用其作为有效标记正好匹配数据就绪时刻。
    // ==================================================================

    always @(posedge i_ext_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            fifo_pipe_data  <= 16'd0;
            fifo_pipe_valid <= 1'b0;
            fifo_last_pipe  <= 1'b0;
        end else begin
            // 采样 PP FIFO 数据 + last_word 标志 (async_fifo 已于同一 i_ext_clk 上升沿更新)
            fifo_pipe_data  <= i_frame_fifo_data;
            fifo_last_pipe  <= i_frame_fifo_last_word;

            // 管道有效: rd_en_was_active 说明上一拍已在 transmit 状态,
            // async_fifo 已至少完成一次读出, 数据就绪。
            if (rd_en_was_active && state_next != S_IDLE)
                fifo_pipe_valid <= 1'b1;
            else
                fifo_pipe_valid <= 1'b0;
        end
    end

    // ==================================================================
    // 反相时钟上升沿输出 — Slave FIFO 数据 / 有效标志 / frame_done_n
    //
    //   o_frame_done_n 与最后一字同步: fifo_pipe_valid=1 时,
    //   fifo_last_pipe=1 表示当前管道数据是帧最后一字,
    //   此时将 frame_done_n 拉低, EZ-USB 在上升沿打包上传。
    //   使用 i_ext_clk_n 上升沿 (等效原下降沿), 使 Slave FIFO 输出
    //   在主时钟上升沿前稳定, 满足 FX2 建立时间要求。
    // ==================================================================

    always @(posedge i_ext_clk_n or negedge i_rst_n) begin
        if (!i_rst_n) begin
            slave_data_reg    <= 16'd0;
            slave_valid_n_reg <= 1'b1;
            frame_done_n_reg  <= 1'b1;
        end else begin
            // 管道数据有效时输出到 Slave FIFO
            if (fifo_pipe_valid) begin
                slave_data_reg    <= fifo_pipe_data;
                slave_valid_n_reg <= 1'b0;
                // fifo_last_pipe=1 时当前字为帧最后一字, 同步拉低 frame_done_n
                frame_done_n_reg  <= !fifo_last_pipe;
            end else begin
                slave_valid_n_reg <= 1'b1;
                frame_done_n_reg  <= 1'b1;
            end
        end
    end

    assign o_slave_fifo_data       = slave_data_reg;
    assign o_slave_fifo_data_valid_n = slave_valid_n_reg;
    assign o_frame_done_n          = frame_done_n_reg;

endmodule

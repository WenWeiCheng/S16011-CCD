`timescale 1ns / 1ps
//==============================================================================
// Module : ccd_clk_gen
// Desc   : CCD 统一时钟生成器 (合并原 ccd_phase_gen + cdsclk_gen)
//          使用单一自由计数器产生全部相位时钟,从硬件层面保证 SCLK/RG 与 CDSCLK
//          之间的固定相位关系,消除双计数器可能引起的相位漂移。
//
//          输出:
//          - 4 相 50% 占空比 SCLK : o_sclk_p0 / o_sclk_p90 / o_sclk_p180 / o_sclk_p270
//          - 2 相 25% 占空比 RG   : o_rg_p90  (90°,  [T/4, T/2))
//                                   o_rg_p270 (270°, [3T/4, T))
//          - 2 相 12.5% 占空比 CDSCLK :
//            CDSCLK1 : 180° 起始 [T/2 + delay, T/2 + delay + T/8)
//            CDSCLK2 : 270° 起始 [3T/4 + delay, 3T/4 + delay + T/8)
//
//          频率通过 i_freq_sel 在 100kHz / 500kHz 之间切换。
//          i_delay 可微调 CDSCLK 脉冲位置 (单位系统时钟周期,自动钳位至 ≤ T/8)。
//==============================================================================
module ccd_clk_gen #(
    parameter SYS_CLK_FREQ_HZ = 100_000_000   // 输入时钟频率 (Hz),按实际板卡修改
) (
    input  wire i_clk,         // 系统时钟
    input  wire i_rst_n,       // 异步复位,低有效
    input  wire i_freq_sel,    // 0 -> 100kHz, 1 -> 500kHz
    input  wire [6:0] i_delay, // CDSCLK 微调延时,单位系统时钟周期,最大 T/8
    // --- SCLK 相位输出 (50% 占空比) ---
    output reg  o_sclk_p0,     // 相位 0°   (复位 0)
    output reg  o_sclk_p90,    // 相位 90°  (复位 0)
    output reg  o_sclk_p180,   // 相位 180° (复位 1)
    output reg  o_sclk_p270,   // 相位 270° (复位 0)
    // --- RG 输出 (25% 占空比) ---
    output reg  o_rg_p90,      // 相位 90°  高电平 [T/4, T/2)   (复位 1)
    output reg  o_rg_p270,     // 相位 270° 高电平 [3T/4, T)     (复位 1)
    // --- CDS 采样时钟 (12.5% 占空比) ---
    output reg  o_cdsclk1,     // CDSCLK1 : 180° 起始 (复位 0)
    output reg  o_cdsclk2      // CDSCLK2 : 270° 起始 (复位 0)
);

    // ==================================================================
    // 参数计算
    // ==================================================================
    localparam [31:0] PERIOD_100K = SYS_CLK_FREQ_HZ / 100_000;  // 例: 100M/100k = 1000
    localparam [31:0] PERIOD_500K = SYS_CLK_FREQ_HZ / 500_000;  // 例: 100M/500k = 200

    // ==================================================================
    // 内部控制信号
    // ==================================================================
    reg  [31:0] period_reg;     // 当前 SCLK 周期的系统时钟个数
    reg  [31:0] cnt_reg;        // 自由计数器: 0 ~ period_reg-1
    wire [31:0] quarter_cnt;    // T/4
    wire [31:0] half_cnt;       // T/2
    wire [31:0] three_q_cnt;    // 3T/4
    wire [31:0] eighth_cnt;     // T/8

    // CDSCLK 区间计算 (组合逻辑)
    wire [31:0] delay_clamped;
    wire [31:0] cdsclk1_start;
    wire [31:0] cdsclk1_end;
    wire [31:0] cdsclk2_start;
    wire [31:0] cdsclk2_end;
    wire        cdsclk2_wrap;
    wire [31:0] cdsclk2_end_wrapped;

    wire sclk_p0_c;
    wire sclk_p90_c;
    wire sclk_p180_c;
    wire sclk_p270_c;
    wire rg_p90_c;
    wire rg_p270_c;
    wire cdsclk1_c;
    wire cdsclk2_c;

    // ==================================================================
    // 频率选择
    // ==================================================================
    always @(*) begin
        case (i_freq_sel)
            1'b0:    period_reg = PERIOD_100K;
            1'b1:    period_reg = PERIOD_500K;
            default: period_reg = PERIOD_100K;
        endcase
    end

    // ==================================================================
    // 自由计数器 (0 ~ period_reg-1)
    // ==================================================================
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n)
            cnt_reg <= 32'd0;
        else if (cnt_reg == period_reg - 1'b1)
            cnt_reg <= 32'd0;
        else
            cnt_reg <= cnt_reg + 1'b1;
    end

    // ==================================================================
    // 时间边界常量
    // ==================================================================
    assign quarter_cnt = period_reg >> 2;              // period / 4
    assign half_cnt    = period_reg >> 1;              // period / 2
    assign three_q_cnt = period_reg - quarter_cnt;     // 3 * period / 4
    assign eighth_cnt  = period_reg >> 3;              // period / 8

    // ==================================================================
    // CDSCLK 区间计算
    // ==================================================================
    // 延时钳位: i_delay 不能超过 T/8
    assign delay_clamped = (i_delay > eighth_cnt) ? eighth_cnt : i_delay;

    // CDSCLK1: [half_cnt + delay, half_cnt + delay + eighth_cnt)
    assign cdsclk1_start = half_cnt + delay_clamped;
    assign cdsclk1_end   = cdsclk1_start + eighth_cnt;

    // CDSCLK2: [three_q_cnt + delay, three_q_cnt + delay + eighth_cnt)
    //   可能跨越周期边界, 需绕回处理
    assign cdsclk2_start = three_q_cnt + delay_clamped;
    assign cdsclk2_end   = cdsclk2_start + eighth_cnt;
    assign cdsclk2_wrap  = (cdsclk2_end >= period_reg);
    assign cdsclk2_end_wrapped = cdsclk2_end - period_reg;

    // ==================================================================
    // SCLK / RG 相位解码 (组合逻辑)
    // ==================================================================
    assign sclk_p0_c   = (cnt_reg <  half_cnt);                                  // [0,    T/2)
    assign sclk_p90_c  = (cnt_reg >= quarter_cnt) && (cnt_reg <  three_q_cnt);   // [T/4, 3T/4)
    assign sclk_p180_c = (cnt_reg >= half_cnt);                                  // [T/2,  T)
    assign sclk_p270_c = (cnt_reg >= three_q_cnt) || (cnt_reg <  quarter_cnt);   // [3T/4, T) U [0, T/4)
    assign rg_p90_c    = (cnt_reg >= quarter_cnt) && (cnt_reg <  half_cnt);      // [T/4, T/2)
    assign rg_p270_c   = (cnt_reg >= three_q_cnt);                               // [3T/4, T)

    // ==================================================================
    // CDSCLK 相位解码 (组合逻辑)
    // ==================================================================
    assign cdsclk1_c = (cnt_reg >= cdsclk1_start) && (cnt_reg < cdsclk1_end);

    assign cdsclk2_c = cdsclk2_wrap ?
        ((cnt_reg >= cdsclk2_start) || (cnt_reg < cdsclk2_end_wrapped)) :
        ((cnt_reg >= cdsclk2_start) && (cnt_reg < cdsclk2_end));

    // ==================================================================
    // 输出寄存器 (统一时钟域, 避免毛刺)
    // ==================================================================
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            o_sclk_p0   <= 1'b0;
            o_sclk_p90  <= 1'b0;
            o_sclk_p180 <= 1'b1;
            o_sclk_p270 <= 1'b0;
            o_rg_p90    <= 1'b1;
            o_rg_p270   <= 1'b1;
            o_cdsclk1   <= 1'b0;
            o_cdsclk2   <= 1'b0;
        end else begin
            o_sclk_p0   <= sclk_p0_c;
            o_sclk_p90  <= sclk_p90_c;
            o_sclk_p180 <= sclk_p180_c;
            o_sclk_p270 <= sclk_p270_c;
            o_rg_p90    <= rg_p90_c;
            o_rg_p270   <= rg_p270_c;
            o_cdsclk1   <= cdsclk1_c;
            o_cdsclk2   <= cdsclk2_c;
        end
    end

endmodule

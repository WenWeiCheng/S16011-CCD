`timescale 1ns / 1ps
//==============================================================================
// Module : ccd_phase_gen
// Desc   : CCD 移位/采样相位时钟生成器
//          - 4 相 50% 占空比 SCLK : o_sclk_p0 / o_sclk_p90 / o_sclk_p180 / o_sclk_p270
//          - 2 相 25% 占空比 RG   : o_rg_p90  (90°,  [T/4, T/2))
//                                   o_rg_p270 (270°, [3T/4, T))
//          频率通过 i_freq_sel 在 100kHz / 500kHz 之间切换
//==============================================================================
module ccd_phase_gen #(
    parameter SYS_CLK_FREQ_HZ = 100_000_000   // 输入时钟频率 (Hz),按实际板卡修改
) (
    input  wire i_clk,         // 系统时钟
    input  wire i_rst_n,       // 异步复位,低有效
    input  wire i_freq_sel,    // 0 -> 100kHz, 1 -> 500kHz
    output reg  o_sclk_p0,     // 相位 0°   50% 占空比 (参考)
    output reg  o_sclk_p90,    // 相位 90°  50% 占空比
    output reg  o_sclk_p180,   // 相位 180° 50% 占空比 (复位高)
    output reg  o_sclk_p270,   // 相位 270° 50% 占空比
    output reg  o_rg_p90,      // 相位 90°  25% 占空比,高电平区间 [T/4, T/2) (复位高)
    output reg  o_rg_p270      // 相位 270° 25% 占空比,高电平区间 [3T/4, T) (复位高)
);

    // 一个完整 SCLK 周期对应的输入时钟个数
    localparam [31:0] PERIOD_100K = SYS_CLK_FREQ_HZ / 100_000;  // 例:100M/100k = 1000
    localparam [31:0] PERIOD_500K = SYS_CLK_FREQ_HZ / 500_000;  // 例:100M/500k = 200

    reg [31:0] period_reg;     // 当前 SCLK 周期的输入时钟个数
    reg [31:0] cnt_reg;        // 自由计数器: 0 ~ period_reg-1

    // 频率选择
    always @(*) begin
        case (i_freq_sel)
            1'b0:    period_reg = PERIOD_100K;
            1'b1:    period_reg = PERIOD_500K;
            default: period_reg = PERIOD_100K;
        endcase
    end

    // 自由计数器
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n)
            cnt_reg <= 32'd0;
        else if (cnt_reg == period_reg - 1'b1)
            cnt_reg <= 32'd0;
        else
            cnt_reg <= cnt_reg + 1'b1;
    end

    // 四分之一周期边界
    wire [31:0] quarter_cnt = period_reg >> 2;              // period / 4
    wire [31:0] half_cnt    = period_reg >> 1;              // period / 2
    wire [31:0] three_q_cnt = period_reg - quarter_cnt;     // 3 * period / 4

    // 相位解码,经寄存器输出避免毛刺
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            o_sclk_p0   <= 1'b0;
            o_sclk_p90  <= 1'b0;
            o_sclk_p180 <= 1'b1;
            o_sclk_p270 <= 1'b0;
            o_rg_p90    <= 1'b1;
            o_rg_p270   <= 1'b1;
        end else begin
            o_sclk_p0   <= (cnt_reg <  half_cnt);                                  // [0,    T/2)
            o_sclk_p90  <= (cnt_reg >= quarter_cnt) && (cnt_reg <  three_q_cnt);   // [T/4, 3T/4)
            o_sclk_p180 <= (cnt_reg >= half_cnt);                                  // [T/2,  T)
            o_sclk_p270 <= (cnt_reg >= three_q_cnt) || (cnt_reg <  quarter_cnt);   // [3T/4, T) U [0, T/4)
            o_rg_p90    <= (cnt_reg >= quarter_cnt) && (cnt_reg <  half_cnt);      // [T/4, T/2)
            o_rg_p270   <= (cnt_reg >= three_q_cnt);                               // [3T/4, T)
        end
    end

endmodule
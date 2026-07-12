`timescale 1ns / 1ps
//==============================================================================
// Module : cdsclk_gen
// Desc   : CDS 采样时钟 (CDSCLK1 / CDSCLK2) 生成器。
//          - 同频于 ccd_phase_gen (通过 i_freq_sel 选择 100kHz / 500kHz)
//          - CDSCLK1 : 相位 180° (T/2 起始), 12.5% 占空比 (T/8 脉宽)
//          - CDSCLK2 : 相位 270° (3T/4 起始), 12.5% 占空比 (T/8 脉宽)
//          - i_delay 可微调时钟时刻 (整体平移), 单位系统时钟周期 (10ns),
//            自动钳位至 ≤ T/8
//          - i_enable 门控输出, 低电平时输出复位值 0
//==============================================================================
module cdsclk_gen #(
    parameter SYS_CLK_FREQ_HZ = 100_000_000   // 输入时钟频率 (Hz)
) (
    input  wire        i_clk,          // 系统时钟
    input  wire        i_rst_n,        // 异步复位, 低有效
    input  wire        i_freq_sel,     // 0 -> 100kHz, 1 -> 500kHz
    input  wire [6:0]  i_delay,        // 微调延时, 单位系统时钟周期, 最大 T/8
    output reg         o_cdsclk1,      // CDSCLK1 : 180° 相位, 12.5% 占空比, 复位 0
    output reg         o_cdsclk2       // CDSCLK2 : 270° 相位, 12.5% 占空比, 复位 0
);

    // 一个完整 SCLK 周期对应的输入时钟个数
    localparam [31:0] PERIOD_100K = SYS_CLK_FREQ_HZ / 100_000;
    localparam [31:0] PERIOD_500K = SYS_CLK_FREQ_HZ / 500_000;

    reg [31:0] period_reg;     // 当前周期的输入时钟个数
    reg [31:0] cnt_reg;        // 自由计数器: 0 ~ period_reg-1

    // ------------------------------------------------------------------
    // 频率选择
    // ------------------------------------------------------------------
    always @(*) begin
        case (i_freq_sel)
            1'b0:    period_reg = PERIOD_100K;
            1'b1:    period_reg = PERIOD_500K;
            default: period_reg = PERIOD_100K;
        endcase
    end

    // ------------------------------------------------------------------
    // 自由计数器
    // ------------------------------------------------------------------
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n)
            cnt_reg <= 32'd0;
        else if (cnt_reg == period_reg - 1'b1)
            cnt_reg <= 32'd0;
        else
            cnt_reg <= cnt_reg + 1'b1;
    end

    // ------------------------------------------------------------------
    // 时间边界常量
    // ------------------------------------------------------------------
    wire [31:0] half_cnt    = period_reg >> 1;              // T/2  (180°)
    wire [31:0] quarter_cnt = period_reg >> 2;              // T/4  (90°)
    wire [31:0] three_q_cnt = period_reg - quarter_cnt;     // 3T/4 (270°)
    wire [31:0] eighth_cnt  = period_reg >> 3;              // T/8  (45°)

    // ------------------------------------------------------------------
    // 延时钳位: i_delay 不能超过 T/8
    // ------------------------------------------------------------------
    wire [31:0] delay_clamped = (i_delay > eighth_cnt) ? eighth_cnt : i_delay;

    // ------------------------------------------------------------------
    // CDSCLK1 区间: [half_cnt + delay, half_cnt + delay + eighth_cnt)
    //   最大: start = T/2 + T/8 = 5T/8, end = 5T/8 + T/8 = 3T/4
    //   始终在 [T/2, 3T/4) 内, 不跨周期边界
    // ------------------------------------------------------------------
    wire [31:0] cdsclk1_start = half_cnt + delay_clamped;
    wire [31:0] cdsclk1_end   = cdsclk1_start + eighth_cnt;
    wire        cdsclk1_active;

    assign cdsclk1_active = (cnt_reg >= cdsclk1_start) && (cnt_reg < cdsclk1_end);

    // ------------------------------------------------------------------
    // CDSCLK2 区间: [three_q_cnt + delay, three_q_cnt + delay + eighth_cnt)
    //   最大: start = 3T/4 + T/8 = 7T/8, end = 7T/8 + T/8 = T (period)
    //   可能跨越周期边界, 需绕回处理
    // ------------------------------------------------------------------
    wire [31:0] cdsclk2_start = three_q_cnt + delay_clamped;
    wire [31:0] cdsclk2_end   = cdsclk2_start + eighth_cnt;
    wire        cdsclk2_wrap  = (cdsclk2_end >= period_reg);
    wire [31:0] cdsclk2_end_wrapped = cdsclk2_end - period_reg;
    wire        cdsclk2_active;

    assign cdsclk2_active = cdsclk2_wrap ?
        ((cnt_reg >= cdsclk2_start) || (cnt_reg < cdsclk2_end_wrapped)) :
        ((cnt_reg >= cdsclk2_start) && (cnt_reg < cdsclk2_end));

    // ------------------------------------------------------------------
    // 输出寄存器 (长期使能, 由 ccd_driver 外部门控)
    // ------------------------------------------------------------------
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            o_cdsclk1 <= 1'b0;
            o_cdsclk2 <= 1'b0;
        end else begin
            o_cdsclk1 <= cdsclk1_active;
            o_cdsclk2 <= cdsclk2_active;
        end
    end

endmodule

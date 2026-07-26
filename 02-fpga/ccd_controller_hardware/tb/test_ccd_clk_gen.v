`timescale 1ns / 1ps
//==============================================================================
// Module : test_ccd_clk_gen
// Desc   : ccd_clk_gen 功能验证 (合并 ccd_phase_gen + cdsclk_gen)
//
//   测试 1 : 复位 — i_rst_n 拉低后所有输出为复位值
//   测试 2 : 100kHz — SCLK 4 相 50% + RG 2 相 25% + CDSCLK 2 相 12.5%
//   测试 3 : 500kHz — 同上,频率切换后波形比例不变
//   测试 4 : i_delay 延时 — 验证 CDSCLK 脉冲整体平移
//   测试 5 : i_delay 超限钳位 — 验证 i_delay > T/8 被截断
//   测试 6 : SCLK-CDSCLK 相位关系 — 验证共用一个计数器,相位锁定
//==============================================================================
module test_ccd_clk_gen;

    parameter real SYS_CLK_PERIOD_NS = 10.0;   // 100 MHz

    reg         i_clk;
    reg         i_rst_n;
    reg         i_freq_sel;
    reg  [6:0]  i_delay;
    wire        o_sclk_p0;
    wire        o_sclk_p90;
    wire        o_sclk_p180;
    wire        o_sclk_p270;
    wire        o_rg_p90;
    wire        o_rg_p270;
    wire        o_cdsclk1;
    wire        o_cdsclk2;

    ccd_clk_gen u_dut (
        .i_clk      (i_clk),
        .i_rst_n    (i_rst_n),
        .i_freq_sel (i_freq_sel),
        .i_delay    (i_delay),
        .o_sclk_p0  (o_sclk_p0),
        .o_sclk_p90 (o_sclk_p90),
        .o_sclk_p180(o_sclk_p180),
        .o_sclk_p270(o_sclk_p270),
        .o_rg_p90   (o_rg_p90),
        .o_rg_p270  (o_rg_p270),
        .o_cdsclk1  (o_cdsclk1),
        .o_cdsclk2  (o_cdsclk2)
    );

    // 系统时钟
    initial i_clk = 1'b0;
    always #(SYS_CLK_PERIOD_NS / 2.0) i_clk = ~i_clk;

    // 任务: 等待指定数量的系统时钟周期
    task wait_cycles(input integer cycles);
        repeat (cycles) @(posedge i_clk);
    endtask

    // ------------------------------------------------------------------
    // 主测试序列
    // ------------------------------------------------------------------
    initial begin
        // ---- 初始状态 ----
        i_rst_n    = 1'b0;
        i_freq_sel = 1'b0;       // 100kHz
        i_delay    = 7'd0;

        // 复位 20 个系统时钟周期
        wait_cycles(20);

        // ==============================================================
        // 测试 1: 复位值检查
        //   o_sclk_p0=0, o_sclk_p90=0, o_sclk_p180=1, o_sclk_p270=0
        //   o_rg_p90=1, o_rg_p270=1, o_cdsclk1=0, o_cdsclk2=0
        // ==============================================================
        i_rst_n = 1'b1;
        wait_cycles(100);

        // ==============================================================
        // 测试 2: 100kHz, i_delay=0
        //   T = 1000 sys_clk (10 us)
        //   SCLK: p0=[0,500), p90=[250,750), p180=[500,1000), p270=[750,1000)U[0,250)
        //   RG  : p90=[250,500), p270=[750,1000)
        //   CDSCLK1: [500, 625), CDSCLK2: [750, 875)
        // ==============================================================
        i_delay  = 7'd0;
        wait_cycles(2000);

        // ==============================================================
        // 测试 3: 500kHz, i_delay=0
        //   T = 200 sys_clk (2 us)
        //   SCLK: p0=[0,100), p90=[50,150), p180=[100,200), p270=[150,200)U[0,50)
        //   RG  : p90=[50,100), p270=[150,200)
        //   CDSCLK1: [100, 125), CDSCLK2: [150, 175)
        // ==============================================================
        i_freq_sel = 1'b1;
        wait_cycles(500);

        // ==============================================================
        // 测试 4: i_delay 延时 (500kHz)
        //   delay=10 → CDSCLK 脉冲整体平移 10 个 sys_clk
        //   CDSCLK1: [110, 135), CDSCLK2: [160, 185)
        // ==============================================================
        i_delay = 7'd10;
        wait_cycles(500);

        // ==============================================================
        // 测试 5: i_delay 超限钳位 (500kHz)
        //   T/8 = 25, delay=50 应被钳位到 25
        //   CDSCLK1: [125, 150), CDSCLK2: [175, 200) → wrap 到 [0, 0)
        // ==============================================================
        i_delay = 7'd50;
        wait_cycles(500);

        // 回到 100kHz 测试钳位
        i_freq_sel = 1'b0;
        //   T/8 = 125, delay=200 应被钳位到 125
        //   CDSCLK1: [625, 750), CDSCLK2: [875, 1000) → wrap 到 [0, 0)
        i_delay = 7'd127;
        wait_cycles(2000);

        // ==============================================================
        // 测试 6: SCLK-CDSCLK 固定相位关系
        //   cdsclk1 的上升沿应与 sclk_p180 的上升沿对齐 (delay=0 时)
        //   cdsclk2 的上升沿应与 sclk_p270 的上升沿对齐 (delay=0 时)
        //   复位后重新以 100kHz, delay=0 运行一周期观察
        // ==============================================================
        i_rst_n = 1'b0;
        wait_cycles(10);
        i_rst_n    = 1'b1;
        i_freq_sel = 1'b0;
        i_delay    = 7'd0;
        wait_cycles(2000);

        // 结束
        wait_cycles(50);
        $finish;
    end

endmodule

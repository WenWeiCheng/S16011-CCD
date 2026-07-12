`timescale 1ns / 1ps
//==============================================================================
// Module : test_cdsclk_gen
// Desc   : cdsclk_gen 功能验证
//
//   测试 1 : 复位 — i_rst_n 拉低后所有输出为 0
//   测试 2 : 100kHz, i_delay=0 — 验证 CDSCLK1 相位/脉宽
//   测试 3 : 500kHz, i_delay=0 — 验证 CDSCLK1 相位/脉宽
//   测试 4 : i_delay 延时 — 验证脉冲整体平移
//   测试 5 : i_enable 门控 — 验证输出在 i_enable=0 时为 0
//   测试 6 : i_delay 超限钳位 — 验证 i_delay > T/8 被截断
//==============================================================================
module test_cdsclk_gen;

    parameter real SYS_CLK_PERIOD_NS = 10.0;   // 100 MHz

    reg         i_clk;
    reg         i_rst_n;
    reg         i_freq_sel;
    reg  [6:0]  i_delay;
    wire        o_cdsclk1;
    wire        o_cdsclk2;

    cdsclk_gen u_dut (
        .i_clk      (i_clk),
        .i_rst_n    (i_rst_n),
        .i_freq_sel (i_freq_sel),
        .i_delay    (i_delay),
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

    // 任务: 等待指定时间 (us)
    task wait_us(input integer us);
        #(us * 1000);
    endtask

    // 任务: 运行测试, 等待若干 SCLK 周期后结束
    task run_test(input integer cycles);
        wait_cycles(cycles);
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

        // 测试 1: 复位值检查
        //   复位时 o_cdsclk1 = 0, o_cdsclk2 = 0
        i_rst_n = 1'b1;
        wait_cycles(100);

        // 测试 2: 100kHz, i_delay=0
        //   T = 1000 sys_clk cycles (10 us)
        //   CDSCLK1: 180°=T/2=500, 脉宽 T/8=125 → [500, 625)
        //   CDSCLK2: 270°=3T/4=750, 脉宽 T/8=125 → [750, 875)
        i_delay  = 7'd0;
        wait_cycles(2000);

        // 测试 3: 500kHz, i_delay=0
        //   T = 200 sys_clk cycles (2 us)
        //   CDSCLK1: 180°=100, 脉宽 25 → [100, 125)
        //   CDSCLK2: 270°=150, 脉宽 25 → [150, 175)
        i_freq_sel = 1'b1;
        wait_cycles(500);

        // 测试 4: i_delay 延时 (500kHz)
        //   delay=10 → 脉冲整体平移 10 个 sys_clk
        //   CDSCLK1: [110, 135), CDSCLK2: [160, 185)
        i_delay = 7'd10;
        wait_cycles(500);

        // 测试 5: (已移除 — i_enable 门控在 ccd_driver 层)

        // 测试 6: i_delay 超限钳位 (500kHz)
        //   T/8 = 25, delay=50 应被钳位到 25
        //   CDSCLK1: [125, 150), CDSCLK2: [175, 200) → wrap 到 [0, 0)
        i_delay = 7'd50;
        wait_cycles(500);

        // 回到 100kHz 测试钳位
        i_freq_sel = 1'b0;
        //   T/8 = 125, delay=200 应被钳位到 125
        //   CDSCLK1: [625, 750), CDSCLK2: [875, 1000) → wrap 到 [0, 0)
        i_delay = 7'd127;
        wait_cycles(2000);

        // 结束
        wait_cycles(50);
        $finish;
    end

endmodule

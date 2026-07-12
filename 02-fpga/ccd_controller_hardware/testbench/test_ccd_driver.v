`timescale 1ns / 1ps
//==============================================================================
// Module : test_ccd_driver
// Desc   : ccd_driver 完整功能验证
//
//   测试 1 : 复位 — i_rst_n 拉低后所有输出为复位值
//   测试 2 : v=4, h=8, l=1 完整周期 — 单行读出
//   测试 3 : v=1, h=8, l=3 完整周期 — 三行分别读出
//   测试 4 : exposure 打断 — 运行中拉高 i_exposure,验证回到 IDLE
//   测试 5 : freq_sel 打断 — 运行中切换 i_freq_sel,验证回到 IDLE
//   测试 6 : i_rst_n 打断 — 运行中拉低 i_rst_n,验证回到 IDLE
//   测试 7 : ADC 数据拼接 — 验证 ADCCLK 双沿采样拼合 16bit 像素数据
//==============================================================================
module test_ccd_driver;

    parameter real SYS_CLK_PERIOD_NS = 10.0;   // 100 MHz

    reg         i_clk;
    reg         i_rst_n;
    reg         i_exposure;
    reg         i_freq_sel;
    reg  [15:0] i_image_width;
    reg  [15:0] i_image_height;
    reg  [3:0]  i_bevel_left;
    reg  [3:0]  i_bevel_top;
    reg  [3:0]  i_bevel_right;
    reg  [3:0]  i_bevel_bottom;
    reg  [3:0]  i_blank_left;
    reg  [3:0]  i_blank_right;
    reg  [1:0]  i_read_mode;
    reg  [7:0]  i_adc_data;
    reg  [6:0]  i_cdsclk_delay;
    wire        o_adcclk;
    wire        o_p1v;
    wire        o_p2v_tg;
    wire        o_p1h;
    wire        o_p2h;
    wire        o_p3h;
    wire        o_p4h_sg;
    wire        o_rg;
    wire        o_cdsclk1;
    wire        o_cdsclk2;
    wire        o_data_valid;
    wire [1:0]  o_pixel_type;
    wire [15:0] o_pixel_data;

    ccd_driver u_dut (
        .i_clk         (i_clk),
        .i_rst_n       (i_rst_n),
        .i_exposure    (i_exposure),
        .i_freq_sel    (i_freq_sel),
        .i_image_width (i_image_width),
        .i_image_height(i_image_height),
        .i_bevel_left  (i_bevel_left),
        .i_bevel_top   (i_bevel_top),
        .i_bevel_right (i_bevel_right),
        .i_bevel_bottom(i_bevel_bottom),
        .i_blank_left  (i_blank_left),
        .i_blank_right (i_blank_right),
        .i_read_mode   (i_read_mode),
        .i_adc_data    (i_adc_data),
        .o_adcclk     (o_adcclk),
        .o_p1v        (o_p1v),
        .o_p2v_tg     (o_p2v_tg),
        .o_p1h        (o_p1h),
        .o_p2h        (o_p2h),
        .o_p3h        (o_p3h),
        .o_p4h_sg     (o_p4h_sg),
        .o_rg         (o_rg),
        .o_cdsclk1    (o_cdsclk1),
        .o_cdsclk2    (o_cdsclk2),
        .i_cdsclk_delay(i_cdsclk_delay),
        .o_data_valid (o_data_valid),
        .o_pixel_type (o_pixel_type),
        .o_pixel_data (o_pixel_data)
    );

    // 系统时钟
    initial i_clk = 1'b0;
    always #(SYS_CLK_PERIOD_NS / 2.0) i_clk = ~i_clk;

    // 任务:等待指定数量的 SCLK (sclk_p0) 周期
    task wait_sclk(input integer cycles);
        repeat (cycles) @(posedge u_dut.sclk_p0_w);
    endtask

    // 任务:等待指定时间(us)
    task wait_us(input integer us);
        #(us * 1000);
    endtask

    // ------------------------------------------------------------------
    // ADC 数据驱动
    //   模拟 ADC 在 ADCCLK 上升/下降沿交替输出 8bit 数据。
    //
    //   adc_cnt 在每个 ADCCLK 周期递增一次,
    //   高字节 = {adc_cnt, 4'hA}, 低字节 = {adc_cnt, 4'h5},
    //   则 o_pixel_data 应 = {adc_cnt, 4'hA, adc_cnt, 4'h5}。
    //   例如: cnt=0 → 0x0A05, cnt=1 → 0x1A15, cnt=2 → 0x2A25...
    // ------------------------------------------------------------------
    reg [3:0] adc_cnt;

    always @(posedge o_adcclk) begin
        adc_cnt     <= adc_cnt + 1'b1;
        i_adc_data  <= {adc_cnt, 4'hA};
    end

    always @(negedge o_adcclk) begin
        i_adc_data <= {adc_cnt, 4'h5};
    end

    // ------------------------------------------------------------------
    // 主激励
    // ------------------------------------------------------------------
    initial begin
        // ================================================================
        // 基础图像参数 (h 方向固定,整个仿真不变)
        //   v = bevel_top(1) + image_height(2) + bevel_bottom(1) = 4
        //   h = blank_left(1) + image_width(4) + bevel_left(1)
        //   l = 1 (line binning)
        //     + bevel_right(1) + blank_right(1) = 8
        // ================================================================
        i_freq_sel     = 1'b0;
        i_rst_n        = 1'b0;
        i_exposure     = 1'b1;       // 初始拉高,避免复位后立即触发
        i_image_width  = 16'd4;
        i_image_height = 16'd2;
        i_bevel_left   = 4'd1;
        i_bevel_top    = 4'd1;
        i_bevel_right  = 4'd1;
        i_bevel_bottom = 4'd1;
        i_blank_left   = 4'd1;
        i_blank_right  = 4'd1;
        i_read_mode    = 2'd0;       // 0=line binning
        i_adc_data     = 8'd0;
        i_cdsclk_delay = 7'd0;
        adc_cnt        = 4'd0;

        // 保持复位 5 个系统时钟,让 phase_gen 稳定
        #(5 * SYS_CLK_PERIOD_NS);

        // ================================================================
        // 测试 1: 复位
        // ================================================================
        @(negedge i_clk);
        i_rst_n = 1'b1;
        // 复位释放后,exposure=1 保持 IDLE
        wait_sclk(2);

        // ================================================================
        // 测试 2: line binning 模式
        //   V(4) + H(12) = 16 SCLK ≈ 160 us @100kHz
        //   同时驱动 ADC 数据,验证像素拼接
        // ================================================================
        i_read_mode    = 2'd0;       // line binning

        // exposure 下降沿触发离开 IDLE
        @(negedge i_clk);
        i_exposure = 1'b0;

        // 等待足够时间完成 1 轮 V+H+回到 IDLE
        wait_us(300);

        // ================================================================
        // 测试 3: image 模式, v=1, h=8, l=3
        //   v = 1 (image 模式固定)
        //   l = bevel_top(1) + image_height(1) + bevel_bottom(1) = 3
        //   3 × (1+12) = 39 SCLK ≈ 390 us
        // ================================================================
        i_read_mode    = 2'd1;       // image

        @(negedge i_clk);
        i_exposure = 1'b1;
        wait_sclk(1);
        @(negedge i_clk);
        i_exposure = 1'b0;

        wait_us(450);

        // ================================================================
        // 测试 4: exposure 打断
        // ================================================================
        @(negedge i_clk);
        i_exposure = 1'b1;
        wait_us(3);
        i_exposure = 1'b0;
        wait_us(100);               // 约 10 SCLK,应在 HORIZONTAL 阶段内
        @(negedge i_clk);
        i_exposure = 1'b1;
        wait_sclk(3);

        // ================================================================
        // 测试 5: freq_sel 打断
        // ================================================================
        @(negedge i_clk);
        i_exposure = 1'b0;
        wait_us(80);
        @(posedge i_clk);
        i_freq_sel = 1'b1;
        wait_sclk(3);

        // ================================================================
        // 测试 6: i_rst_n 打断
        // ================================================================
        @(posedge i_clk);
        i_freq_sel = 1'b0;
        wait_us(30);

        @(negedge i_clk);
        i_exposure = 1'b1;
        wait_us(3);
        i_exposure = 1'b0;
        wait_us(80);
        @(negedge i_clk);
        i_rst_n = 1'b0;
        #(5 * SYS_CLK_PERIOD_NS);
        @(negedge i_clk);
        i_rst_n = 1'b1;
        wait_sclk(2);
        @(negedge i_clk);
        i_exposure = 1'b1;
        wait_sclk(2);

        $finish;
    end

endmodule
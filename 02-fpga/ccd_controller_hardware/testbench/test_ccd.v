`timescale 1ns / 1ps
//==============================================================================
// Module : test_ccd
// Desc   : ccd 顶层模块联合测试 (ccd_driver + ccd_frame_buf)
//
//   测试 1 : line binning 模式 — 触发一帧 → 帧缓存接收 → 读出验证
//   测试 2 : image 模式 — 触发一帧 → 帧缓存接收 → 读出验证
//   测试 3 : 乒乓双帧 — 连续触发两帧 → full=1 → 读出两帧
//   测试 4 : exposure 打断 — 运行中拉高 exposure → 回到 IDLE
//==============================================================================
module test_ccd;

    parameter real SYS_CLK_PERIOD_NS = 10.0;    // 100 MHz
    parameter real RD_CLK_PERIOD_NS  = 40.0;    // 25 MHz

    // ---- 系统 ----
    reg         i_clk;
    reg         i_rst_n;

    // ---- CCD 控制 ----
    reg         i_exposure;
    reg         i_freq_sel;
    reg  [6:0]  i_cdsclk_delay;

    // ---- 图像参数 ----
    reg  [15:0] i_image_width;
    reg  [15:0] i_image_height;
    reg  [3:0]  i_bevel_left;
    reg  [3:0]  i_bevel_top;
    reg  [3:0]  i_bevel_right;
    reg  [3:0]  i_bevel_bottom;
    reg  [3:0]  i_blank_left;
    reg  [3:0]  i_blank_right;
    reg  [1:0]  i_read_mode;

    // ---- ADC 数据 ----
    reg  [7:0]  i_adc_data;

    // ---- CCD 驱动信号 ----
    wire o_adcclk;
    wire o_p1v;
    wire o_p2v_tg;
    wire o_p1h;
    wire o_p2h;
    wire o_p3h;
    wire o_p4h_sg;
    wire o_rg;
    wire o_cdsclk1;
    wire o_cdsclk2;

    // ---- 帧缓存读侧 ----
    reg         i_rd_clk;
    wire [15:0] o_fifo_data;
    wire        o_fifo_empty;
    wire        o_fifo_half_full;
    wire        o_fifo_full;
    reg         i_fifo_rd_en;
    wire        o_rd_fifo_sel;
    wire        o_frame_exception;

    // ==================================================================
    // DUT
    // ==================================================================
    ccd #(
        .MAX_FRAME_DEPTH(256)
    ) u_dut (
        .i_clk           (i_clk),
        .i_rst_n         (i_rst_n),
        .i_exposure      (i_exposure),
        .i_freq_sel      (i_freq_sel),
        .i_cdsclk_delay  (i_cdsclk_delay),
        .i_image_width   (i_image_width),
        .i_image_height  (i_image_height),
        .i_bevel_left    (i_bevel_left),
        .i_bevel_top     (i_bevel_top),
        .i_bevel_right   (i_bevel_right),
        .i_bevel_bottom  (i_bevel_bottom),
        .i_blank_left    (i_blank_left),
        .i_blank_right   (i_blank_right),
        .i_read_mode     (i_read_mode),
        .i_adc_data      (i_adc_data),
        .o_adcclk        (o_adcclk),
        .o_p1v           (o_p1v),
        .o_p2v_tg        (o_p2v_tg),
        .o_p1h           (o_p1h),
        .o_p2h           (o_p2h),
        .o_p3h           (o_p3h),
        .o_p4h_sg        (o_p4h_sg),
        .o_rg            (o_rg),
        .o_cdsclk1       (o_cdsclk1),
        .o_cdsclk2       (o_cdsclk2),
        .i_rd_clk        (i_rd_clk),
        .o_fifo_data     (o_fifo_data),
        .o_fifo_empty    (o_fifo_empty),
        .o_fifo_half_full(o_fifo_half_full),
        .o_fifo_full     (o_fifo_full),
        .i_fifo_rd_en    (i_fifo_rd_en),
        .o_rd_fifo_sel   (o_rd_fifo_sel),
        .o_frame_exception(o_frame_exception)
    );

    // ==================================================================
    // 时钟生成
    // ==================================================================
    initial i_clk = 1'b0;
    always #(SYS_CLK_PERIOD_NS / 2.0) i_clk = ~i_clk;

    initial i_rd_clk = 1'b0;
    always #(RD_CLK_PERIOD_NS / 2.0) i_rd_clk = ~i_rd_clk;

    // ==================================================================
    // ADC 数据驱动
    //   模拟 ADC 在 ADCCLK 上升/下降沿交替输出 8bit 数据。
    //   高字节 = {adc_cnt, 4'hA}, 低字节 = {adc_cnt, 4'h5}
    //   → o_pixel_data = {adc_cnt_rise, 4'hA, adc_cnt_fall, 4'h5}
    // ==================================================================
    reg [3:0] adc_cnt;

    always @(posedge o_adcclk) begin
        adc_cnt    <= adc_cnt + 1'b1;
        i_adc_data <= {adc_cnt, 4'hA};
    end

    always @(negedge o_adcclk) begin
        i_adc_data <= {adc_cnt, 4'h5};
    end

    // ==================================================================
    // 辅助任务
    // ==================================================================

    // ---- 等待指定微秒数 ----
    task wait_us(input integer us);
        begin
            #(us * 1000);
        end
    endtask

    // ---- 等待读时钟周期 ----
    task rd_wait(input integer cycles);
        begin
            repeat (cycles) @(posedge i_rd_clk);
        end
    endtask

    // ---- 从帧缓存读出一个像素 ----
    reg [15:0] rd_result;
    task rd_pixel;
        begin
            @(negedge i_rd_clk);
            i_fifo_rd_en <= 1'b1;
            @(posedge i_rd_clk);
            i_fifo_rd_en <= 1'b0;
            @(negedge i_rd_clk);
            @(posedge i_rd_clk);
            rd_result = o_fifo_data;
        end
    endtask

    // ---- 读出 N 个像素 ----
    task rd_pixels(input integer num);
        integer k;
        begin
            for (k = 0; k < num; k = k + 1) begin
                rd_pixel;
            end
        end
    endtask

    // ---- 等待 CDC 稳定 ----
    task wait_cdc;
        begin
            rd_wait(20);
        end
    endtask

    // ==================================================================
    // 主激励
    // ==================================================================
    initial begin : stimulus

        // ---- 初始化 ----
        i_freq_sel     = 1'b0;        // 100kHz SCLK
        i_rst_n        = 1'b0;
        i_exposure     = 1'b1;
        i_image_width  = 16'd4;
        i_image_height = 16'd2;
        i_bevel_left   = 4'd1;
        i_bevel_top    = 4'd1;
        i_bevel_right  = 4'd1;
        i_bevel_bottom = 4'd1;
        i_blank_left   = 4'd1;
        i_blank_right  = 4'd1;
        i_read_mode    = 2'd0;        // line binning
        i_adc_data     = 8'd0;
        i_cdsclk_delay = 7'd0;
        i_fifo_rd_en   = 1'b0;
        adc_cnt        = 4'd0;

        // 保持复位
        #(5 * SYS_CLK_PERIOD_NS);
        i_rst_n = 1'b1;
        wait_us(5);

        // ================================================================
        // 测试 1: line binning 模式 — 单帧写入 + 读出
        //   v=4, h=8, l=1, frame_depth = 4 active 像素
        // ================================================================
        i_read_mode = 2'd0;

        // 触发 exposure 下降沿
        @(negedge i_clk);
        i_exposure = 1'b0;

        // 等待一帧完成 (v=4 + h≈14 = ~18 SCLK ≈ 180us, 多等一些)
        wait_us(300);

        // 拉高 exposure, 回到 IDLE
        i_exposure = 1'b1;
        wait_cdc;

        // 读出一帧 (4 个 active 像素)
        rd_pixels(4);
        wait_cdc;

        // ================================================================
        // 测试 2: image 模式 — 单帧写入 + 读出
        //   bevel_top/bottom=0, 使 frame_depth = image_width * image_height
        //   v=1, h=8, l=2, frame_depth = 4*2 = 8 active 像素
        // ================================================================
        i_read_mode    = 2'd1;
        i_bevel_top    = 4'd0;
        i_bevel_bottom = 4'd0;

        @(negedge i_clk);
        i_exposure = 1'b0;

        // 等待一帧完成 (l*(v+h) ≈ 2*15 = 30 SCLK ≈ 300us)
        wait_us(400);

        i_exposure = 1'b1;
        wait_cdc;

        // 读出 8 个 active 像素
        rd_pixels(8);
        wait_cdc;

        // ================================================================
        // 测试 3: 乒乓双帧 — 连续两帧 → full=1 → 读出两帧
        //   用 line binning 模式 (帧短, 仿真快)
        // ================================================================
        i_read_mode = 2'd0;

        // 帧 1
        @(negedge i_clk);
        i_exposure = 1'b0;
        wait_us(300);
        i_exposure = 1'b1;
        wait_us(50);

        // 帧 2
        @(negedge i_clk);
        i_exposure = 1'b0;
        wait_us(300);
        i_exposure = 1'b1;
        wait_cdc;

        // 读出帧 1
        rd_pixels(4);
        wait_cdc;

        // 读出帧 2
        rd_pixels(4);
        wait_cdc;

        // ================================================================
        // 测试 4: exposure 打断 — 运行中拉高, 验证回到 IDLE
        // ================================================================
        @(negedge i_clk);
        i_exposure = 1'b0;
        wait_us(80);                 // 约 8 SCLK, 应在 HORIZONTAL 阶段内
        @(negedge i_clk);
        i_exposure = 1'b1;           // 打断
        wait_us(60);

        $finish;
    end

endmodule

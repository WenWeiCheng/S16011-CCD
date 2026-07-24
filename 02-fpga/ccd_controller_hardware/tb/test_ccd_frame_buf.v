`timescale 1ns / 1ps
//==============================================================================
// Module : test_ccd_frame_buf
// Desc   : ccd_frame_buf 乒乓帧缓存功能验证
//
//   测试 1 : 复位 — o_fifo_empty=1, half_full=0, full=0
//   测试 2 : 单帧写入 — 8 active 像素 → half_full=1, 数据正确
//   测试 3 : 单帧读出 — 读 8 像素 → empty=1, 数据匹配
//   测试 4 : 乒乓切换 — 写 2 帧 → full=1, 读 1 帧 → half_full=1
//   测试 5 : 边写边读 — 帧 0 写入同时帧 1 读出
//   测试 6 : 帧长异常 — active 像素 != frame_depth → o_frame_exception
//   测试 7 : 像素类型过滤 — 仅 active(10) 像素被计数/写入
//   测试 8 : S2/S3 等待态 — 读写速率不匹配时暂停写入
//==============================================================================
module test_ccd_frame_buf;

    parameter MAX_FRAME_DEPTH     = 256;        // TB 用小深度加速仿真
    parameter real WR_CLK_PERIOD  = 2000.0;     // 500kHz (2us)
    parameter real RD_CLK_PERIOD  = 40.0;       // 25MHz

    // ---- 写侧 ----
    reg         i_adcclk;
    reg         i_rst_n;
    reg  [15:0] i_wr_data;
    reg         i_wr_en;
    reg  [1:0]  i_pixel_type;
    reg         i_frame_start;
    reg         i_frame_end;
    reg  [15:0] i_image_width;
    reg  [15:0] i_image_height;
    reg  [1:0]  i_read_mode;

    // ---- 读侧 ----
    reg         i_rd_clk;
    wire [15:0] o_fifo_data;
    wire [1:0]  o_frame_num;
    reg         i_fifo_rd_en;

    // ---- 异常 ----
    wire        o_frame_exception;
    reg [15:0] rd_result;
    integer i;

    // ==================================================================
    // DUT
    // ==================================================================
    ccd_frame_buf #(
        .MAX_FRAME_DEPTH(MAX_FRAME_DEPTH)
    ) u_dut (
        .i_adcclk          (i_adcclk),
        .i_rst_n           (i_rst_n),
        .i_wr_data         (i_wr_data),
        .i_wr_en           (i_wr_en),
        .i_pixel_type      (i_pixel_type),
        .i_frame_start     (i_frame_start),
        .i_frame_end       (i_frame_end),
        .i_image_width     (i_image_width),
        .i_image_height    (i_image_height),
        .i_read_mode       (i_read_mode),
        .i_rd_clk          (i_rd_clk),
        .o_fifo_data       (o_fifo_data),
        .o_frame_num       (o_frame_num),
        .i_fifo_rd_en      (i_fifo_rd_en),
        .o_frame_exception (o_frame_exception)
    );

    // ==================================================================
    // 时钟生成
    // ==================================================================
    initial i_adcclk = 1'b0;
    always #(WR_CLK_PERIOD / 2.0) i_adcclk = ~i_adcclk;

    initial i_rd_clk = 1'b0;
    always #(RD_CLK_PERIOD / 2.0) i_rd_clk = ~i_rd_clk;

    // ==================================================================
    // 辅助任务
    // ==================================================================

    // ---- 写域等待 ----
    task wr_wait(input integer cycles);
        repeat (cycles) @(posedge i_adcclk);
    endtask

    // ---- 读域等待 ----
    task rd_wait(input integer cycles);
        repeat (cycles) @(posedge i_rd_clk);
    endtask

    // ---- 写入一个像素 (active 类型) ----
    task wr_active_pixel(input [15:0] data);
        begin
            @(posedge i_adcclk);
            i_wr_data    <= data;
            i_wr_en      <= 1'b1;
            i_pixel_type <= 2'b10;  // active
            @(posedge i_adcclk);
            i_wr_en      <= 1'b0;
            i_pixel_type <= 2'b00;
        end
    endtask

    // ---- 写入一个像素 (指定类型) ----
    task wr_pixel(input [15:0] data, input [1:0] ptype);
        begin
            @(posedge i_adcclk);
            i_wr_data    <= data;
            i_wr_en      <= 1'b1;
            i_pixel_type <= ptype;
            @(posedge i_adcclk);
            i_wr_en      <= 1'b0;
            i_pixel_type <= 2'b00;
        end
    endtask

    // ---- 写入一帧 active 像素 ----
    //   frame_end 为脉冲: 一帧结束时单周期拉高
    task wr_frame(input integer num_active);
        integer k;
        begin
            // 帧开始: frame_start 脉冲
            // 设置 width=num_active, height=1, read_mode=0(line binning) → frame_depth = width
            i_image_width  <= num_active;
            i_image_height <= 1;
            i_read_mode    <= 2'd0;
            @(posedge i_adcclk);
            i_frame_start <= 1'b1;
            @(posedge i_adcclk);
            i_frame_start <= 1'b0;

            // 写入 active 像素 (frame_end 保持低)
            for (k = 0; k < num_active; k = k + 1) begin
                wr_active_pixel(16'd1000 + k);
            end

            // 帧结束: frame_end 单周期脉冲
            @(posedge i_adcclk);
            i_frame_end <= 1'b1;
            @(posedge i_adcclk);
            i_frame_end <= 1'b0;
            wr_wait(5);  // CDC 读→写 延迟余量 (wr_enable 需要 2-3 adcclk 周期生效)
        end
    endtask

    // ---- 写入一帧 (含 blank/bevel 前后像素) ----
    task wr_frame_with_overhead(input integer num_active,
                                input integer num_blank_before,
                                input integer num_blank_after);
        integer k;
        begin
            i_image_width  <= num_active;
            i_image_height <= 1;
            i_read_mode    <= 2'd0;
            @(posedge i_adcclk);
            i_frame_start <= 1'b1;
            @(posedge i_adcclk);
            i_frame_start <= 1'b0;

            // 前置 blank 像素
            for (k = 0; k < num_blank_before; k = k + 1) begin
                wr_pixel(16'hBEEF, 2'b01);
            end

            // active 像素
            for (k = 0; k < num_active; k = k + 1) begin
                wr_active_pixel(16'd2000 + k);
            end

            // 后置 blank 像素
            for (k = 0; k < num_blank_after; k = k + 1) begin
                wr_pixel(16'hDEAD, 2'b01);
            end

            // 帧结束脉冲
            @(posedge i_adcclk);
            i_frame_end <= 1'b1;
            @(posedge i_adcclk);
            i_frame_end <= 1'b0;
            wr_wait(5);  // CDC 读→写 延迟余量
        end
    endtask

    // ---- 读取一个像素 (返回读到的值) ----
    //   async_fifo 在 negedge 更新 o_rd_data, posedge 采样
    task rd_pixel;
        begin
            @(posedge i_rd_clk);
            i_fifo_rd_en <= 1'b1;
            @(posedge i_rd_clk);   // DUT 采样 i_fifo_rd_en
            i_fifo_rd_en <= 1'b0;
            @(posedge i_rd_clk);   // DUT 更新 o_rd_data
            @(posedge i_rd_clk);   // 采样稳定数据
            rd_result = o_fifo_data;
        end
    endtask

    // ---- 读取 N 个像素, 与期望值比较 ----
    task rd_frame_verify(input integer num,
                         input [15:0] expected_base);
        integer k;
        begin
            for (k = 0; k < num; k = k + 1) begin
                rd_pixel;
                if (rd_result !== expected_base + k) begin
                    $display("[FAIL] pixel[%0d]: expected 0x%04h, got 0x%04h",
                             k, expected_base + k, rd_result);
                    $stop;
                end
            end
        end
    endtask

    // ---- 等待 CDC 稳定 (给跨时钟域同步留时间) ----
    task wait_cdc;
        begin
            wr_wait(10);
            rd_wait(10);
        end
    endtask

    // ==================================================================
    // 主激励
    // ==================================================================

    initial begin : stimulus
        $display("========================================");
        $display(" ccd_frame_buf Testbench");
        $display("========================================");

        // ---- 初始化 ----
        i_rst_n       = 1'b0;
        i_wr_data     = 16'd0;
        i_wr_en       = 1'b0;
        i_pixel_type  = 2'b00;
        i_frame_start = 1'b0;
        i_frame_end    = 1'b0;
        i_image_width  = 16'd0;
        i_image_height = 16'd1;
        i_read_mode    = 2'd0;
        i_fifo_rd_en   = 1'b0;

        wr_wait(5);
        i_rst_n = 1'b1;
        wr_wait(5);
        rd_wait(5);

        // ================================================================
        // 测试 1: 复位后状态
        // ================================================================
        $display("[TEST 1] Reset check");
        if (o_frame_num !== 2'd0) begin
            $display("[FAIL] Reset state: frame_num=%d (expected 0)",
                     o_frame_num);
        end else begin
            $display("[PASS] Reset state OK");
        end

        // ================================================================
        // 测试 2: 单帧写入
        // ================================================================
        $display("[TEST 2] Single frame write (8 active pixels)");
        wr_frame(8);
        wait_cdc;

        if (o_frame_num !== 2'd1) begin
            $display("[FAIL] After write 1 frame: frame_num=%d (expected 1)",
                     o_frame_num);
        end else begin
            $display("[PASS] frame_num=1 after 1 frame written");
        end

        // ================================================================
        // 测试 3: 单帧读出 + 数据验证
        // ================================================================
        $display("[TEST 3] Single frame read (8 pixels)");
        rd_frame_verify(8, 16'd1000);
        wait_cdc;

        if (o_frame_num !== 2'd0) begin
            $display("[FAIL] After read 1 frame: frame_num=%d (expected 0)",
                     o_frame_num);
        end else begin
            $display("[PASS] frame_num=0 after frame read");
        end

        // ================================================================
        // 测试 4: 乒乓切换 (写 2 帧 → 读 1 帧 → 读 1 帧)
        // ================================================================
        $display("[TEST 4] Ping-pong: write 2 frames, then read both");
        wr_frame(8);   // frame 0 → frame_num=1
        wr_frame(8);   // frame 1 → frame_num=2
        wait_cdc;

        if (o_frame_num !== 2'd2) begin
            $display("[FAIL] After 2 frames: frame_num=%d (expected 2)", o_frame_num);
        end else begin
            $display("[PASS] frame_num=2 after 2 frames written");
        end

        rd_frame_verify(8, 16'd1000);  // 读帧 0
        wait_cdc;

        if (o_frame_num !== 2'd1) begin
            $display("[FAIL] After reading 1 of 2 frames: frame_num=%d (expected 1)",
                     o_frame_num);
        end else begin
            $display("[PASS] frame_num=1 after reading 1 frame");
        end

        rd_frame_verify(8, 16'd1000);  // 读帧 1
        wait_cdc;

        if (o_frame_num !== 2'd0) begin
            $display("[FAIL] After reading both frames: frame_num=%d (expected 0)",
                     o_frame_num);
        end else begin
            $display("[PASS] frame_num=0 after reading all frames");
        end

        // ================================================================
        // 测试 5: 边写边读 (模拟正常乒乓流程)
        //   写帧 A → 同时启动读帧 A + 写帧 B → 读完 A → 读 B
        // ================================================================
        $display("[TEST 5] Concurrent write/read (ping-pong normal flow)");

        // 先清空
        if (o_frame_num != 0) begin
            // 如果还有残留帧, 先读空
            while (o_frame_num != 0) rd_pixel;
        end

        wr_frame(8);  // 写帧 A (进 fifo0)
        wait_cdc;
        $display("  Frame A written, frame_num=%d", o_frame_num);

        // 同时: 读帧 A + 写帧 B
        // 先启动读 (读出帧 A 的前几个像素)
        fork
            begin : write_frame_b
                wr_frame(16);  // 写帧 B (进 fifo1, 不同深度验证)
            end
            begin : read_frame_a
                rd_wait(1);
                // 读出帧 A
                for (i = 0; i < 8; i = i + 1) begin
                    rd_pixel;
                    if (rd_result !== 16'd1000 + i) begin
                        $display("[FAIL] Concurrent: pixel[%0d]=0x%04h, expected 0x%04h",
                                 i, rd_result, 16'd1000 + i);
                    end
                end
            end
        join

        wait_cdc;
        $display("  Frame B written + Frame A read, frame_num=%d",
                 o_frame_num);

        // 读帧 B
        rd_frame_verify(16, 16'd1000);

        wait_cdc;
        if (o_frame_num !== 2'd0) begin
            $display("[FAIL] Concurrent test: final frame_num=%d", o_frame_num);
        end else begin
            $display("[PASS] Concurrent write/read OK");
        end

        // ================================================================
        // 测试 6: 帧长异常 (pixel count != frame_depth)
        // ================================================================
        $display("[TEST 6] Frame length exception");

        // 写入少于 frame_depth 的 active 像素 → 应触发 exception
        @(posedge i_adcclk);
        i_image_width  <= 8;
        i_image_height <= 1;
        i_read_mode    <= 2'd0;
        i_frame_start  <= 1'b1;
        @(posedge i_adcclk);
        i_frame_start <= 1'b0;

        // 只写 5 个 active 像素 (设定为 8)
        for (i = 0; i < 5; i = i + 1) begin
            wr_active_pixel(16'd3000 + i);
        end

        // 帧结束脉冲
        @(posedge i_adcclk);
        i_frame_end <= 1'b1;
        @(posedge i_adcclk);
        i_frame_end <= 1'b0;
        wr_wait(5);

        $display("  Frame exception test: check waveform for exception pulse");

        // 异常后全局复位, 清理状态机
        i_rst_n = 1'b0;
        wr_wait(5);
        rd_wait(5);
        i_rst_n = 1'b1;
        wr_wait(10);
        rd_wait(10);

        // ================================================================
        // 测试 7: 像素类型过滤 (仅 active 被写入子 FIFO)
        // ================================================================
        $display("[TEST 7] Pixel type filtering");

        wr_frame_with_overhead(8, 4, 4);
        wait_cdc;

        if (o_frame_num !== 2'd1) begin
            $display("[FAIL] Pixel filter: frame_num=%d after frame with overhead",
                     o_frame_num);
        end else begin
            $display("[PASS] Frame recognized despite blank/bevel pixels");
        end

        // 读出验证数据 (只有 active 像素进入 FIFO)
        rd_frame_verify(8, 16'd2000);
        $display("[PASS] Only active pixel data in FIFO");

        // ================================================================
        // 测试 8: S2/S3 等待态 — 写满两个 FIFO 但不读
        // ================================================================
        $display("[TEST 8] S2/S3 wait states");

        // 读空 test 7 残留
        while (o_frame_num != 0) rd_pixel;
        wait_cdc;

        // 连续写 2 帧
        wr_frame(8);  // frame 0
        wr_frame(8);  // frame 1
        wait_cdc;

        if (o_frame_num !== 2'd2) begin
            $display("[FAIL] S2/S3: frame_num=%d after 2 frames", o_frame_num);
        end else begin
            $display("[PASS] frame_num=2 after 2 frames (both FIFOs have ready frame)");
        end

        // 尝试写第 3 帧 — 状态机应进入 S2/S3 等待
        @(posedge i_adcclk);
        i_image_width  <= 8;
        i_image_height <= 1;
        i_read_mode    <= 2'd0;
        i_frame_start  <= 1'b1;
        @(posedge i_adcclk);
        i_frame_start <= 1'b0;

        for (i = 0; i < 8; i = i + 1) begin
            wr_active_pixel(16'd4000 + i);
        end

        @(posedge i_adcclk);
        i_frame_end <= 1'b1;
        @(posedge i_adcclk);
        i_frame_end <= 1'b0;
        wr_wait(5);

        $display("  S2/S3 test: check waveform for state transition");

        // 读空所有帧
        while (o_frame_num != 0) rd_pixel;
        wait_cdc;

        $display("========================================");
        $display(" All tests completed");
        $display("========================================");
        $finish;
    end

endmodule

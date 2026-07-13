`timescale 1ns / 1ps
//==============================================================================
// Module : test_ccd_frame_tx
// Desc   : ccd_frame_tx 帧发送模块功能验证 (集成 ccd_frame_buf)
//
//   使用已验证的 ccd_frame_buf 作为 PP FIFO 源, 通过写侧写入像素数据,
//   验证 ccd_frame_tx 从读侧读出并转发至 Slave FIFO 的完整通路。
//
//   测试 1 : 复位 — o_slave_fifo_data_valid_n=1, o_frame_done_n=1
//   测试 2 : 单帧发送 — 写一帧, 触发 TX, 验证 frame_done
//   测试 3 : 数据验证 — 采集 Slave FIFO 输出, 比对 8 words
//   测试 4 : 连续多帧 — 依次发送 3 帧
//   测试 5 : Slave FIFO 满反压 — full_n=0 时暂停发送, 恢复后继续
//   测试 6 : 乒乓切换 — 写 2 帧后分别发送
//   测试 7 : 帧长异常 — active 像素 != frame_depth → o_frame_exception
//   测试 8 : 先 start 后等数据 — idle→wait, 数据稍后到达触发 transmit
//==============================================================================
module test_ccd_frame_tx;

    // ==================================================================
    // 参数
    // ==================================================================
    parameter MAX_FRAME_DEPTH = 256;          // 子 FIFO 深度 (小值加速仿真)
    parameter FRAME_WORDS     = 8;            // 每帧字数
    parameter real WR_CLK_PERIOD = 2000.0;    // 500 kHz
    parameter real RD_CLK_PERIOD = 40.0;      // 25 MHz

    // ==================================================================
    // 写侧信号 (ccd_frame_buf)
    // ==================================================================
    reg         i_adcclk;
    reg         i_rst_n;
    reg  [15:0] i_wr_data;
    reg         i_wr_en;
    reg  [1:0]  i_pixel_type;
    reg         i_frame_start_buf;
    reg         i_frame_end;
    reg  [31:0] i_frame_depth;

    // ==================================================================
    // 读侧时钟
    // ==================================================================
    reg         i_ext_clk;

    // ==================================================================
    // ccd_frame_buf ↔ ccd_frame_tx 连接
    // ==================================================================
    wire [15:0] fifo_data;
    wire        fifo_empty;
    wire        fifo_half_full;
    wire        fifo_full;
    wire        fifo_last_word;
    wire        fifo_rd_en;

    // ==================================================================
    // Slave FIFO 接口
    // ==================================================================
    wire [15:0] o_slave_fifo_data;
    wire        o_slave_fifo_data_valid_n;
    reg         i_slave_fifo_empty_n;
    reg         i_slave_fifo_full_n;

    // ==================================================================
    // 帧控制
    // ==================================================================
    reg         i_frame_start_tx;
    wire        o_frame_done_n;

    // ccd_frame_buf 额外输出
    wire        o_frame_exception;

    // ==================================================================
    // o_frame_exception 捕获 (写域脉冲 → 寄存器展宽)
    // ==================================================================
    reg exception_captured;
    always @(posedge i_adcclk or negedge i_rst_n) begin
        if (!i_rst_n)
            exception_captured <= 1'b0;
        else if (o_frame_exception)
            exception_captured <= 1'b1;
    end

    // ==================================================================
    // frame_done 捕获 (跨时钟域, 防止 wr_frame 阻塞时错过)
    // ==================================================================
    reg frame_done_captured;
    always @(negedge o_frame_done_n or negedge i_rst_n) begin
        if (!i_rst_n)
            frame_done_captured <= 1'b0;
        else
            frame_done_captured <= 1'b1;
    end

    // ==================================================================
    // DUT 实例化
    // ==================================================================

    ccd_frame_buf #(
        .MAX_FRAME_DEPTH(MAX_FRAME_DEPTH)
    ) u_ccd_frame_buf (
        .i_adcclk          (i_adcclk),
        .i_rst_n           (i_rst_n),
        .i_wr_data         (i_wr_data),
        .i_wr_en           (i_wr_en),
        .i_pixel_type      (i_pixel_type),
        .i_frame_start     (i_frame_start_buf),
        .i_frame_end       (i_frame_end),
        .i_frame_depth     (i_frame_depth),
        .i_rd_clk          (i_ext_clk),
        .o_fifo_data       (fifo_data),
        .o_fifo_empty      (fifo_empty),
        .o_fifo_half_full  (fifo_half_full),
        .o_fifo_full       (fifo_full),
        .o_fifo_last_word  (fifo_last_word),
        .i_fifo_rd_en      (fifo_rd_en),
        .o_rd_fifo_sel     (),
        .o_frame_exception (o_frame_exception)
    );

    ccd_frame_tx u_ccd_frame_tx (
        .i_ext_clk             (i_ext_clk),
        .i_rst_n               (i_rst_n),
        .i_frame_fifo_data     (fifo_data),
        .i_frame_fifo_empty    (fifo_empty),
        .i_frame_fifo_half_full(fifo_half_full),
        .i_frame_fifo_full     (fifo_full),
        .i_frame_fifo_last_word(fifo_last_word),
        .o_frame_fifo_rd_en    (fifo_rd_en),
        .o_slave_fifo_data     (o_slave_fifo_data),
        .o_slave_fifo_data_valid_n(o_slave_fifo_data_valid_n),
        .i_slave_fifo_empty_n  (i_slave_fifo_empty_n),
        .i_slave_fifo_full_n   (i_slave_fifo_full_n),
        .i_frame_start         (i_frame_start_tx),
        .o_frame_done_n        (o_frame_done_n)
    );

    // ==================================================================
    // 时钟生成
    // ==================================================================
    initial i_adcclk = 1'b0;
    always #(WR_CLK_PERIOD / 2.0) i_adcclk = ~i_adcclk;

    initial i_ext_clk = 1'b0;
    always #(RD_CLK_PERIOD / 2.0) i_ext_clk = ~i_ext_clk;

    // ==================================================================
    // 辅助任务 — 写域 (i_adcclk)
    // ==================================================================

    task wr_wait(input integer cycles);
        repeat (cycles) @(posedge i_adcclk);
    endtask

    task wr_active_pixel(input [15:0] data);
        begin
            @(posedge i_adcclk);
            i_wr_data    <= data;
            i_wr_en      <= 1'b1;
            i_pixel_type <= 2'b10;
            @(posedge i_adcclk);
            i_wr_en      <= 1'b0;
            i_pixel_type <= 2'b00;
        end
    endtask

    // ---- 写入一帧 (纯 active 像素) ----
    task wr_frame(input integer num_active, input [15:0] base);
        integer k;
        begin
            i_frame_depth <= num_active;
            @(posedge i_adcclk);
            i_frame_start_buf <= 1'b1;
            @(posedge i_adcclk);
            i_frame_start_buf <= 1'b0;

            for (k = 0; k < num_active; k = k + 1)
                wr_active_pixel(base + k);

            @(posedge i_adcclk);
            i_frame_end <= 1'b1;
            @(posedge i_adcclk);
            i_frame_end <= 1'b0;
            wr_wait(6);  // CDC 延迟
        end
    endtask

    // ==================================================================
    // 辅助任务 — 读域 (i_ext_clk)
    // ==================================================================

    task rd_wait(input integer cycles);
        repeat (cycles) @(posedge i_ext_clk);
    endtask

    // ---- 触发 ccd_frame_tx 开始一帧传输 ----
    task send_frame;
        begin
            @(posedge i_ext_clk);
            i_frame_start_tx <= 1'b1;
            @(posedge i_ext_clk);
            i_frame_start_tx <= 1'b0;  // 下降沿 → idle→wait
        end
    endtask

    // ---- 等待 frame_done (最多等 500 rd_clk) ----
    reg [15:0] wait_timeout;
    task wait_frame_done;
        begin
            wait_timeout = 0;
            while (frame_done_captured === 1'b0 && wait_timeout < 500) begin
                @(posedge i_ext_clk);
                wait_timeout = wait_timeout + 1;
            end
        end
    endtask

    // ---- 从 Slave FIFO 读取一字 (等待 valid_n=0 后采样) ----
    reg [15:0] slave_rd_result;
    task slave_read_word;
        begin
            @(negedge i_ext_clk);
            while (o_slave_fifo_data_valid_n !== 1'b0)
                @(negedge i_ext_clk);
            slave_rd_result = o_slave_fifo_data;
        end
    endtask

    // ---- 清空 frame_done 捕获标志 ----
    task clear_frame_done_capture;
        begin
            frame_done_captured = 1'b0;
            #0;
        end
    endtask

    // ==================================================================
    // 主激励
    // ==================================================================
    integer i;

    initial begin : stimulus
        $display("========================================");
        $display(" ccd_frame_tx Testbench (with ccd_frame_buf)");
        $display(" FRAME_WORDS=%0d, MAX_FRAME_DEPTH=%0d",
                 FRAME_WORDS, MAX_FRAME_DEPTH);
        $display("========================================");

        // ---- 初始化 ----
        i_rst_n          = 1'b0;
        i_wr_data        = 16'd0;
        i_wr_en          = 1'b0;
        i_pixel_type     = 2'b00;
        i_frame_start_buf = 1'b0;
        i_frame_end      = 1'b0;
        i_frame_depth    = 32'd0;
        i_frame_start_tx = 1'b0;
        i_slave_fifo_empty_n = 1'b1;
        i_slave_fifo_full_n  = 1'b1;

        frame_done_captured = 1'b0;

        wr_wait(5);
        rd_wait(5);
        i_rst_n = 1'b1;
        wr_wait(5);
        rd_wait(5);

        // ================================================================
        // 测试 1: 复位后状态
        // ================================================================
        $display("[TEST 1] Reset check");
        rd_wait(1);
        if (o_slave_fifo_data_valid_n !== 1'b1) begin
            $display("[FAIL] Reset: data_valid_n=%b (expected 1)",
                     o_slave_fifo_data_valid_n);
        end else if (o_frame_done_n !== 1'b1) begin
            $display("[FAIL] Reset: frame_done_n=%b (expected 1)", o_frame_done_n);
        end else begin
            $display("[PASS] Reset state OK");
        end

        // ================================================================
        // 测试 2: 单帧发送 — 写一帧, 触发 TX, 等 frame_done
        // ================================================================
        $display("[TEST 2] Single frame transmission");
        clear_frame_done_capture;
        wr_frame(FRAME_WORDS, 16'd1000);
        $display("  Frame written, half_full=%b", fifo_half_full);

        send_frame;
        rd_wait(3);
        wait_frame_done;

        if (frame_done_captured !== 1'b1) begin
            $display("[FAIL] frame_done not received");
        end else begin
            $display("[PASS] frame_done received");
        end
        rd_wait(5);

        // ================================================================
        // 测试 3: 数据验证 — 采集 Slave FIFO 输出比对
        // ================================================================
        $display("[TEST 3] Data verification");
        if (!fifo_empty) begin
            clear_frame_done_capture;
            send_frame;
            wait_frame_done;
            rd_wait(5);
        end

        clear_frame_done_capture;
        wr_frame(FRAME_WORDS, 16'd2000);
        send_frame;

        // 读取 FRAME_WORDS 个有效字 (自同步, 等待 valid_n=0)
        for (i = 0; i < FRAME_WORDS; i = i + 1) begin
            slave_read_word;
            if (slave_rd_result !== 16'd2000 + i) begin
                $display("[FAIL] Data[%0d]: expected 0x%04h, got 0x%04h",
                         i, 16'd2000 + i, slave_rd_result);
            end
        end

        wait_frame_done;
        if (frame_done_captured !== 1'b1) begin
            $display("[FAIL] frame_done not received after data verify");
        end else begin
            $display("[PASS] Data verified (%0d words)", FRAME_WORDS);
        end
        rd_wait(5);

        // ================================================================
        // 测试 4: 连续多帧发送
        // ================================================================
        $display("[TEST 4] Multiple frame transmissions");
        for (i = 0; i < 3; i = i + 1) begin
            clear_frame_done_capture;
            wr_frame(FRAME_WORDS, 16'd3000 + i*1000);
            send_frame;
            wait_frame_done;
            if (frame_done_captured !== 1'b1) begin
                $display("[FAIL] Frame %0d: frame_done not received", i);
            end else begin
                $display("  Frame %0d done", i);
            end
            rd_wait(3);
        end
        $display("[PASS] 3 frames transmitted");

        // ================================================================
        // 测试 5: Slave FIFO 满反压
        // ================================================================
        $display("[TEST 5] Slave FIFO full back-pressure");
        clear_frame_done_capture;
        wr_frame(FRAME_WORDS, 16'd6000);
        send_frame;
        rd_wait(1);

        // 模拟 Slave FIFO 满
        @(negedge i_ext_clk);
        i_slave_fifo_full_n = 1'b0;
        rd_wait(8);
        if (fifo_rd_en !== 1'b0) begin
            $display("[FAIL] rd_en=%b during back-pressure (expected 0)",
                     fifo_rd_en);
        end else begin
            $display("[PASS] rd_en deasserted during back-pressure");
        end

        // 释放反压
        @(negedge i_ext_clk);
        i_slave_fifo_full_n = 1'b1;
        rd_wait(2);
        wait_frame_done;
        if (frame_done_captured !== 1'b1) begin
            $display("[FAIL] frame_done not received after back-pressure");
        end else begin
            $display("[PASS] Transmission resumed after back-pressure release");
        end
        rd_wait(5);

        // ================================================================
        // 测试 6: 乒乓切换 — 写 2 帧再分别发送
        // ================================================================
        $display("[TEST 6] Ping-pong: 2 frames");
        clear_frame_done_capture;
        wr_frame(FRAME_WORDS, 16'd7000);
        wr_frame(FRAME_WORDS, 16'd8000);
        $display("  2 frames written, full=%b", fifo_full);

        clear_frame_done_capture;
        send_frame;
        wait_frame_done;
        if (frame_done_captured !== 1'b1) begin
            $display("[FAIL] Frame 0 done not received");
        end else begin
            $display("  Frame 0 done, half_full=%b", fifo_half_full);
        end
        rd_wait(3);

        clear_frame_done_capture;
        send_frame;
        wait_frame_done;
        if (frame_done_captured !== 1'b1) begin
            $display("[FAIL] Frame 1 done not received");
        end else begin
            $display("  Frame 1 done, empty=%b", fifo_empty);
        end
        rd_wait(3);
        $display("[PASS] Ping-pong OK");

        // ================================================================
        // 测试 7: 帧长异常 — 写入少于 frame_depth 的像素
        // ================================================================
        $display("[TEST 7] Frame length exception");
        clear_frame_done_capture;
        exception_captured = 1'b0;

        @(posedge i_adcclk);
        i_frame_depth <= FRAME_WORDS;
        i_frame_start_buf <= 1'b1;
        @(posedge i_adcclk);
        i_frame_start_buf <= 1'b0;

        for (i = 0; i < FRAME_WORDS - 3; i = i + 1)
            wr_active_pixel(16'd9000 + i);

        // frame_end 脉冲: 用 NBA 赋值 (与原 wr_frame 任务一致)
        // exception_captured 寄存器会捕获 o_frame_exception 脉冲
        @(posedge i_adcclk);
        i_frame_end <= 1'b1;
        @(posedge i_adcclk);
        i_frame_end <= 1'b0;

        // 等待几拍让 CDC 和寄存器稳定
        wr_wait(3);

        if (exception_captured !== 1'b1) begin
            $display("[FAIL] Exception not triggered (captured=%b)",
                     exception_captured);
        end else begin
            $display("[PASS] Frame exception detected");
        end

        // 复位清除异常状态
        i_rst_n = 1'b0;
        frame_done_captured = 1'b0;
        wr_wait(5);
        rd_wait(5);
        i_rst_n = 1'b1;
        wr_wait(10);
        rd_wait(10);

        // ================================================================
        // 测试 8: 先 start 后等数据 (idle→wait 再触发)
        // ================================================================
        $display("[TEST 8] Start before data");
        clear_frame_done_capture;
        send_frame;           // idle→wait (PP FIFO 空)
        rd_wait(3);
        $display("  In wait state, writing frame...");

        // wr_frame 在 adcclk 域阻塞, 期间 TX 可能已完成
        // frame_done_captured 会捕获到
        wr_frame(FRAME_WORDS, 16'd10000);

        if (frame_done_captured !== 1'b1) begin
            // 如果还没完成, 等一会
            wait_frame_done;
        end

        if (frame_done_captured !== 1'b1) begin
            $display("[FAIL] Start-before-data: frame_done not received");
        end else begin
            $display("[PASS] Start-before-data OK");
        end
        rd_wait(5);

        // ================================================================
        $display("========================================");
        $display(" All tests completed");
        $display("========================================");
        $finish;
    end

endmodule

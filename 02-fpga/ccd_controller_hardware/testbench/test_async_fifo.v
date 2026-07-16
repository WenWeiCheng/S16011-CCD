`timescale 1ns / 1ps
//==============================================================================
// Module : test_async_fifo
// Desc   : async_fifo 基础功能验证
//
//   测试 1 : 复位 — o_empty=1, o_full=0, o_almost_empty=0
//   测试 2 : 写入 8 个数据 — 填满 FIFO, 验证 o_full=1
//   测试 3 : 读出 8 个数据 — 排空 FIFO, 验证 o_empty=1
//   测试 4 : 绕回测试 — 写 5 → 读 3 → 写 6 → 读 8, 验证数据完整性
//   测试 5 : almost_empty — 1 字时拉高, 读出后变 0
//   测试 6 : almost_empty — 2 字时 0 → 读 1 字后变 1 → 再读变 0
//==============================================================================
module test_async_fifo;

    parameter WR_CLK_PERIOD_NS = 100.0;    // 写时钟 10 MHz
    parameter RD_CLK_PERIOD_NS = 40.0;     // 读时钟 25 MHz
    parameter FIFO_DEPTH       = 8;

    // 写侧信号
    reg                     i_wr_clk;
    reg                     i_rst_n;
    reg  [15:0]             i_wr_data;
    reg                     i_wr_en;
    wire                    o_full;
    wire                    o_almost_full;

    // 读侧信号
    reg                     i_rd_clk;
    wire [15:0]             o_rd_data;
    reg                     i_rd_en;
    wire                    o_empty;
    wire                    o_almost_empty;

    // DUT
    async_fifo #(
        .DATA_WIDTH(16),
        .FIFO_DEPTH(FIFO_DEPTH)
    ) u_dut (
        .i_wr_clk      (i_wr_clk),
        .i_rst_n       (i_rst_n),
        .i_wr_data     (i_wr_data),
        .i_wr_en       (i_wr_en),
        .o_full        (o_full),
        .o_almost_full (o_almost_full),
        .i_rd_clk      (i_rd_clk),
        .o_rd_data     (o_rd_data),
        .i_rd_en       (i_rd_en),
        .o_empty       (o_empty),
        .o_almost_empty(o_almost_empty)
    );

    // 写时钟
    initial i_wr_clk = 1'b0;
    always #(WR_CLK_PERIOD_NS / 2.0) i_wr_clk = ~i_wr_clk;

    // 读时钟
    initial i_rd_clk = 1'b0;
    always #(RD_CLK_PERIOD_NS / 2.0) i_rd_clk = ~i_rd_clk;

    // 任务:写侧等待 N 个写时钟
    task wr_wait(input integer cycles);
        repeat (cycles) @(posedge i_wr_clk);
    endtask

    // 任务:读侧等待 N 个读时钟
    task rd_wait(input integer cycles);
        repeat (cycles) @(posedge i_rd_clk);
    endtask

    // 任务:写入一个数据
    task wr_data(input [15:0] data);
        begin
            @(posedge i_wr_clk);
            i_wr_data <= data;
            i_wr_en   <= 1'b1;
            @(posedge i_wr_clk);
            i_wr_en   <= 1'b0;
        end
    endtask

    // 任务:读取一个数据 (返回读到的值)
    //   negedge 驱动 i_rd_en → posedge DUT 采样 → negedge DUT 更新输出 → posedge sample
    reg [15:0] rd_result;
    task rd_data;
        begin
            @(negedge i_rd_clk);     // 驱动 i_rd_en, setup 到下一个 posedge
            i_rd_en <= 1'b1;
            @(posedge i_rd_clk);     // DUT 在上升沿采样 i_rd_en, 读取 BRAM
            i_rd_en <= 1'b0;          // 撤消使能
            @(negedge i_rd_clk);     // DUT 在下降沿更新 o_rd_data
            @(posedge i_rd_clk);     // 在上升沿采样 (数据自 negedge 后稳定)
            rd_result = o_rd_data;
        end
    endtask

    // ------------------------------------------------------------------
    // 主激励
    // ------------------------------------------------------------------
    integer i;

    initial begin : stimulus
        // ================================================================
        // 初始化
        // ================================================================
        i_rst_n <= 1'b0;
        i_wr_data  <= 16'd0;
        i_wr_en    <= 1'b0;
        i_rd_en    <= 1'b0;

        // 复位保持 5 个写时钟
        wr_wait(5);
        i_rst_n <= 1'b1;
        wr_wait(2);
        rd_wait(2);

        // ================================================================
        // 测试 1 : 复位后状态
        // ================================================================
        // 复位后 o_empty=1, o_full=0
        // (Vivado 波形中观察)

        // ================================================================
        // 测试 2 : 写入 8 个数据, 填满 FIFO
        // ================================================================
        for (i = 0; i < FIFO_DEPTH; i = i + 1) begin
            wr_data(16'd100 + i);
        end
        // 此时 o_full=1, o_empty=0
        wr_wait(1);

        // 尝试再写一个 (应被忽略, o_full 保持)
        wr_data(16'd200);
        wr_wait(1);

        // ================================================================
        // 测试 3 : 读出 8 个数据, 排空 FIFO
        // ================================================================
        for (i = 0; i < FIFO_DEPTH; i = i + 1) begin
            rd_data;
        end
        // 此时 o_empty=1
        rd_wait(1);

        // ================================================================
        // 测试 4 : 绕回测试 — 写 5 → 读 3 → 写 6 → 读 8
        // ================================================================
        // 写 5
        for (i = 0; i < 5; i = i + 1) begin
            wr_data(16'd300 + i);
        end

        // 读 3
        for (i = 0; i < 3; i = i + 1) begin
            rd_data;
        end

        // 写 6
        for (i = 0; i < 6; i = i + 1) begin
            wr_data(16'd400 + i);
        end

        // 读 8 (读空 FIFO)
        for (i = 0; i < 8; i = i + 1) begin
            rd_data;
        end

        // ================================================================
        // 测试 5 : almost_empty — 1 字时拉高, 读出后变 0
        // ================================================================
        // 先确保 FIFO 空
        rd_wait(5);

        // 写 1 字
        wr_data(16'd500);
        // 等待写指针 CDC 到读域 (至少 2 rd_clk)
        rd_wait(5);

        // 此时 FIFO 中有 1 字, 下一拍读出会使 FIFO 变空
        // almost_empty 在 posedge 更新, 采样检查
        @(posedge i_rd_clk);
        if (o_almost_empty !== 1'b1) begin
            $display("[FAIL] Test5: after 1 write, almost_empty=%b (expected 1)",
                     o_almost_empty);
        end else begin
            $display("[PASS] Test5: almost_empty=1 when 1 word in FIFO");
        end

        // 读出该字
        rd_data;

        // 读出后 FIFO 空, almost_empty 应变 0
        @(posedge i_rd_clk);
        #1;
        if (o_almost_empty !== 1'b0) begin
            $display("[FAIL] Test5: after read empty, almost_empty=%b (expected 0)",
                     o_almost_empty);
        end else begin
            $display("[PASS] Test5: almost_empty=0 after FIFO emptied");
        end

        // ================================================================
        // 测试 6 : almost_empty — 2 字时 0 → 读 1 字后变 1 → 再读变 0
        // ================================================================
        // 写 2 字
        wr_data(16'd600);
        wr_data(16'd601);
        rd_wait(5);  // CDC

        // 2 字在 FIFO 中, 读 1 字不会空 → almost_empty=0
        @(posedge i_rd_clk);
        if (o_almost_empty !== 1'b0) begin
            $display("[FAIL] Test6a: with 2 words, almost_empty=%b (expected 0)",
                     o_almost_empty);
        end else begin
            $display("[PASS] Test6a: almost_empty=0 when 2 words in FIFO");
        end

        // 读 1 字, 剩 1 字
        rd_data;
        @(posedge i_rd_clk);
        #1;
        if (o_almost_empty !== 1'b1) begin
            $display("[FAIL] Test6b: after reading 1 of 2, almost_empty=%b (expected 1)",
                     o_almost_empty);
        end else begin
            $display("[PASS] Test6b: almost_empty=1 when 1 word left");
        end

        // 读最后 1 字, FIFO 空
        rd_data;
        @(posedge i_rd_clk);
        #1;
        if (o_almost_empty !== 1'b0) begin
            $display("[FAIL] Test6c: after emptying FIFO, almost_empty=%b (expected 0)",
                     o_almost_empty);
        end else begin
            $display("[PASS] Test6c: almost_empty=0 after FIFO emptied");
        end

        rd_wait(10);
        $display("========================================");
        $display(" All tests completed");
        $display("========================================");
        // 结束
        $finish;
    end

endmodule

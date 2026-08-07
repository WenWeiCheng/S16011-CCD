`timescale 1ns / 1ps
//==============================================================================
// Testbench : test_ccd_frame_buf_ddr
// Desc      : ccd_frame_buf_ddr 顶层模块的完整仿真 testbench
//
// 架构:
//   DUT (ccd_frame_buf_ddr) 内部已封装:
//     ccd_frame_buf_ddr_ctrl (控制逻辑 + wr/rd FIFO + AXI adapter)
//     mig_7series_0 (Xilinx MIG IP)
//
//   Testbench 负责:
//     - 驱动 ADC 时钟域 (i_adcclk): 模拟 CCD 像素数据输入
//     - 驱动 RD 时钟域 (i_rd_clk):  模拟 FX2 读回数据
//     - 例化 DDR3 仿真模型 (ddr3_model × 2: 32-bit → 2×16-bit)
//     - 自检验证写入/读回数据一致性
//
//   FIFO 约束:
//     Xilinx FIFO 实际可用深度 = 配置深度 - 1, 因此:
//       wr_ddr3_fifo: 写侧实际 511 (配置512), 读侧实际 63 (配置64)
//       rd_ddr3_fifo: 写侧实际 63  (配置64),  读侧实际 511 (配置512)
//     测试用例中单帧像素数不应设为 512 的整数倍, 以避免触碰 FIFO 写侧深度边界。
//==============================================================================
module test_ccd_frame_buf_ddr;

    // ==================================================================
    // 参数 (缩减以加速仿真)
    // ==================================================================
    localparam MAX_FRAMES       = 4;
    localparam MAX_FRAME_DEPTH  = 2048;

    localparam ADC_CLK_PERIOD   = 20;     // 50 MHz
    localparam RD_CLK_PERIOD    = 20;     // 50 MHz (与 ADC 异步)
    localparam DDR3_CLK100_PER  = 10;     // 100 MHz
    localparam DDR3_CLK200_PER  = 5;      // 200 MHz ref

    localparam BURST_UNITS      = 32;     // AXI_BURST_LEN + 1
    localparam PIXELS_PER_BURST = BURST_UNITS * 8;  // 256 像素/burst
    localparam FRAME_NUM_W      = $clog2(MAX_FRAMES + 1);

    // ==================================================================
    // 时钟
    // ==================================================================
    reg i_adcclk;
    reg i_rd_clk;
    reg mig_sys_clk;
    reg mig_clk_ref;

    initial i_adcclk = 1'b0;
    always #(ADC_CLK_PERIOD/2) i_adcclk = ~i_adcclk;

    initial i_rd_clk = 1'b0;
    always #(RD_CLK_PERIOD/2) i_rd_clk = ~i_rd_clk;

    initial mig_sys_clk = 1'b0;
    always #(DDR3_CLK100_PER/2) mig_sys_clk = ~mig_sys_clk;

    initial mig_clk_ref = 1'b0;
    always #(DDR3_CLK200_PER/2) mig_clk_ref = ~mig_clk_ref;

    // ==================================================================
    // 复位与 DUT 控制
    // ==================================================================
    reg i_rst_n;
    reg mig_rst_n;   // MIG 专用复位, 独立于 i_rst_n

    // ==================================================================
    // ADC 域信号 (i_adcclk)
    // ==================================================================
    reg  [15:0] i_wr_data;
    reg         i_wr_en;
    reg  [1:0]  i_pixel_type;
    reg         i_frame_start;
    reg         i_frame_end;
    reg  [15:0] i_image_width;
    reg  [15:0] i_image_height;
    reg  [1:0]  i_read_mode;

    // ==================================================================
    // RD 域信号 (i_rd_clk) — 来自 DUT 输出
    // ==================================================================
    wire [15:0]                   o_fifo_data;
    wire [FRAME_NUM_W-1:0]        o_frame_num;
    reg                           i_fifo_rd_en;
    wire                          o_fifo_prelast;

    // ==================================================================
    // 异常 / 状态
    // ==================================================================
    wire o_frame_exception;

    // ---- MIG 接口 (ui_clk 域) ----
    wire        ui_clk;
    wire        ddr3_init_done;
    wire        mmcm_locked;
    wire        init_calib_complete;
    wire        ui_clk_sync_rst;
    // 控制器复位: 系统复位 AND DDR3 初始化完成 (ccd_frame_buf_ddr 不再内部门控)
    wire        ctrl_rst_n = i_rst_n && ddr3_init_done;

    // ==================================================================
    // DDR3 物理接口 (MIG ↔ ddr3_model)
    // ==================================================================
    wire [31:0]  ddr3_dq;
    wire [3:0]   ddr3_dqs_n;
    wire [3:0]   ddr3_dqs_p;
    wire [14:0]  ddr3_addr;
    wire [2:0]   ddr3_ba;
    wire         ddr3_ras_n;
    wire         ddr3_cas_n;
    wire         ddr3_we_n;
    wire         ddr3_reset_n;
    wire [0:0]   ddr3_ck_p;
    wire [0:0]   ddr3_ck_n;
    wire [0:0]   ddr3_cke;
    wire [0:0]   ddr3_cs_n;
    wire [3:0]   ddr3_dm;
    wire [0:0]   ddr3_odt;

    // ---- AXI4 互连 (DUT M_AXI ↔ MIG S_AXI) ----
    wire [3:0]   axi_awid;
    wire [29:0]  axi_awaddr;
    wire [7:0]   axi_awlen;
    wire [2:0]   axi_awsize;
    wire [1:0]   axi_awburst;
    wire         axi_awlock;
    wire [3:0]   axi_awcache;
    wire [2:0]   axi_awprot;
    wire [3:0]   axi_awqos;
    wire         axi_awvalid;
    wire         axi_awready;
    wire [127:0] axi_wdata;
    wire [15:0]  axi_wstrb;
    wire         axi_wlast;
    wire         axi_wvalid;
    wire         axi_wready;
    wire [3:0]   axi_bid;
    wire [1:0]   axi_bresp;
    wire         axi_bvalid;
    wire         axi_bready;
    wire [3:0]   axi_arid;
    wire [29:0]  axi_araddr;
    wire [7:0]   axi_arlen;
    wire [2:0]   axi_arsize;
    wire [1:0]   axi_arburst;
    wire         axi_arlock;
    wire [3:0]   axi_arcache;
    wire [2:0]   axi_arprot;
    wire [3:0]   axi_arqos;
    wire         axi_arvalid;
    wire         axi_arready;
    wire [3:0]   axi_rid;
    wire [127:0] axi_rdata;
    wire [1:0]   axi_rresp;
    wire         axi_rlast;
    wire         axi_rvalid;
    wire         axi_rready;

    // ==================================================================
    // Scoreboard
    // ==================================================================
    reg  [15:0]  scoreboard [0:MAX_FRAMES-1][0:MAX_FRAME_DEPTH-1];

    // ==================================================================
    // 测试控制变量
    // ==================================================================
    integer      frame_i, pixel_i;
    reg   [7:0]  test_num;
    reg  [15:0]  last_img_width;
    reg  [15:0]  last_img_height;
    reg  [1:0]   last_read_mode;

    // ==================================================================
    // DUT 例化 (MIG 已移出, 通过 AXI4 接口连接)
    // ==================================================================
    ccd_frame_buf_ddr #(
        .MAX_FRAME_DEPTH (MAX_FRAME_DEPTH),
        .MAX_FRAMES      (MAX_FRAMES)
    ) u_dut (
        // ADC 域
        .i_wr_clk         (i_adcclk),
        .i_rst_n          (ctrl_rst_n),
        .i_wr_data        (i_wr_data),
        .i_wr_en          (i_wr_en),
        .i_pixel_type     (i_pixel_type),
        .i_frame_start    (i_frame_start),
        .i_frame_end      (i_frame_end),
        .i_image_width    (i_image_width),
        .i_image_height   (i_image_height),
        .i_read_mode      (i_read_mode),

        // RD 域
        .i_rd_clk         (i_rd_clk),
        .o_fifo_data      (o_fifo_data),
        .o_frame_num      (o_frame_num),
        .i_fifo_rd_en     (i_fifo_rd_en),
        .o_fifo_prelast (o_fifo_prelast),

        // 异常
        .o_frame_exception(o_frame_exception),

        // MIG 接口
        .i_ui_clk         (ui_clk),

        // AXI4 Master
        .M_AXI_AWID       (axi_awid),
        .M_AXI_AWADDR     (axi_awaddr),
        .M_AXI_AWLEN      (axi_awlen),
        .M_AXI_AWSIZE     (axi_awsize),
        .M_AXI_AWBURST    (axi_awburst),
        .M_AXI_AWLOCK     (axi_awlock),
        .M_AXI_AWCACHE    (axi_awcache),
        .M_AXI_AWPROT     (axi_awprot),
        .M_AXI_AWQOS      (axi_awqos),
        .M_AXI_AWREGION   (),
        .M_AXI_AWVALID    (axi_awvalid),
        .M_AXI_AWREADY    (axi_awready),
        .M_AXI_WDATA      (axi_wdata),
        .M_AXI_WSTRB      (axi_wstrb),
        .M_AXI_WLAST      (axi_wlast),
        .M_AXI_WVALID     (axi_wvalid),
        .M_AXI_WREADY     (axi_wready),
        .M_AXI_BID        (axi_bid),
        .M_AXI_BRESP      (axi_bresp),
        .M_AXI_BVALID     (axi_bvalid),
        .M_AXI_BREADY     (axi_bready),
        .M_AXI_ARID       (axi_arid),
        .M_AXI_ARADDR     (axi_araddr),
        .M_AXI_ARLEN      (axi_arlen),
        .M_AXI_ARSIZE     (axi_arsize),
        .M_AXI_ARBURST    (axi_arburst),
        .M_AXI_ARLOCK     (axi_arlock),
        .M_AXI_ARCACHE    (axi_arcache),
        .M_AXI_ARPROT     (axi_arprot),
        .M_AXI_ARQOS      (axi_arqos),
        .M_AXI_ARREGION   (),
        .M_AXI_ARVALID    (axi_arvalid),
        .M_AXI_ARREADY    (axi_arready),
        .M_AXI_RID        (axi_rid),
        .M_AXI_RDATA      (axi_rdata),
        .M_AXI_RRESP      (axi_rresp),
        .M_AXI_RLAST      (axi_rlast),
        .M_AXI_RVALID     (axi_rvalid),
        .M_AXI_RREADY     (axi_rready)
    );

    // ==================================================================
    // MIG 7-Series DDR3 Controller (外部例化)
    //   连接 DUT 的 AXI4 Master ↔ MIG S_AXI ↔ DDR3 仿真模型
    // ==================================================================
    assign ddr3_init_done = mmcm_locked && init_calib_complete;

    mig_7series_0 u_mig (
        .ddr3_dq              (ddr3_dq),
        .ddr3_dqs_n           (ddr3_dqs_n),
        .ddr3_dqs_p           (ddr3_dqs_p),
        .ddr3_addr            (ddr3_addr),
        .ddr3_ba              (ddr3_ba),
        .ddr3_ras_n           (ddr3_ras_n),
        .ddr3_cas_n           (ddr3_cas_n),
        .ddr3_we_n            (ddr3_we_n),
        .ddr3_reset_n         (ddr3_reset_n),
        .ddr3_ck_p            (ddr3_ck_p),
        .ddr3_ck_n            (ddr3_ck_n),
        .ddr3_cke             (ddr3_cke),
        .ddr3_cs_n            (ddr3_cs_n),
        .ddr3_dm              (ddr3_dm),
        .ddr3_odt             (ddr3_odt),
        .init_calib_complete  (init_calib_complete),
        .sys_clk_i            (mig_sys_clk),
        .clk_ref_i            (mig_clk_ref),
        .ui_clk               (ui_clk),
        .ui_clk_sync_rst      (ui_clk_sync_rst),
        .mmcm_locked          (mmcm_locked),
        .aresetn              (mig_rst_n),
        .sys_rst              (mig_rst_n),
        .app_sr_req           (1'b0),
        .app_ref_req          (1'b0),
        .app_zq_req           (1'b0),
        .app_sr_active        (),
        .app_ref_ack          (),
        .app_zq_ack           (),
        .s_axi_awid           (axi_awid),
        .s_axi_awaddr         (axi_awaddr),
        .s_axi_awlen          (axi_awlen),
        .s_axi_awsize         (axi_awsize),
        .s_axi_awburst        (axi_awburst),
        .s_axi_awlock         (axi_awlock),
        .s_axi_awcache        (axi_awcache),
        .s_axi_awprot         (axi_awprot),
        .s_axi_awqos          (axi_awqos),
        .s_axi_awvalid        (axi_awvalid),
        .s_axi_awready        (axi_awready),
        .s_axi_wdata          (axi_wdata),
        .s_axi_wstrb          (axi_wstrb),
        .s_axi_wlast          (axi_wlast),
        .s_axi_wvalid         (axi_wvalid),
        .s_axi_wready         (axi_wready),
        .s_axi_bready         (axi_bready),
        .s_axi_bid            (axi_bid),
        .s_axi_bresp          (axi_bresp),
        .s_axi_bvalid         (axi_bvalid),
        .s_axi_arid           (axi_arid),
        .s_axi_araddr         (axi_araddr),
        .s_axi_arlen          (axi_arlen),
        .s_axi_arsize         (axi_arsize),
        .s_axi_arburst        (axi_arburst),
        .s_axi_arlock         (axi_arlock),
        .s_axi_arcache        (axi_arcache),
        .s_axi_arprot         (axi_arprot),
        .s_axi_arqos          (axi_arqos),
        .s_axi_arvalid        (axi_arvalid),
        .s_axi_arready        (axi_arready),
        .s_axi_rready         (axi_rready),
        .s_axi_rid            (axi_rid),
        .s_axi_rdata          (axi_rdata),
        .s_axi_rresp          (axi_rresp),
        .s_axi_rlast          (axi_rlast),
        .s_axi_rvalid         (axi_rvalid)
    );

    // ==================================================================
    // DDR3 仿真模型 × 2 — 参考 fifo_axi4_adapter_tb.v 拼接方式
    //   32-bit DDR3 拆为 2 个 16-bit 模型:
    //     model1: dq[31:16], dqs[3:2], dm[3:2]
    //     model2: dq[15:0],  dqs[1:0], dm[1:0]
    // ==================================================================
    ddr3_model ddr3_model_hi (
        .rst_n  (ddr3_reset_n),
        .ck     (ddr3_ck_p),
        .ck_n   (ddr3_ck_n),
        .cke    (ddr3_cke),
        .cs_n   (ddr3_cs_n),
        .ras_n  (ddr3_ras_n),
        .cas_n  (ddr3_cas_n),
        .we_n   (ddr3_we_n),
        .dm_tdqs(ddr3_dm[3:2]),
        .ba     (ddr3_ba),
        .addr   (ddr3_addr),
        .dq     (ddr3_dq[31:16]),
        .dqs    (ddr3_dqs_p[3:2]),
        .dqs_n  (ddr3_dqs_n[3:2]),
        .tdqs_n (),
        .odt    (ddr3_odt)
    );

    ddr3_model ddr3_model_lo (
        .rst_n  (ddr3_reset_n),
        .ck     (ddr3_ck_p),
        .ck_n   (ddr3_ck_n),
        .cke    (ddr3_cke),
        .cs_n   (ddr3_cs_n),
        .ras_n  (ddr3_ras_n),
        .cas_n  (ddr3_cas_n),
        .we_n   (ddr3_we_n),
        .dm_tdqs(ddr3_dm[1:0]),
        .ba     (ddr3_ba),
        .addr   (ddr3_addr),
        .dq     (ddr3_dq[15:0]),
        .dqs    (ddr3_dqs_p[1:0]),
        .dqs_n  (ddr3_dqs_n[1:0]),
        .tdqs_n (),
        .odt    (ddr3_odt)
    );



    // ==================================================================
    // 辅助 Tasks
    // ==================================================================

    // ------------------------------------------------------------------
    // wait_adc_cycles: 等待 N 个 ADC 时钟周期
    // ------------------------------------------------------------------
    task wait_adc_cycles;
        input integer cycles;
        begin
            repeat(cycles) @(posedge i_adcclk);
        end
    endtask

    // ------------------------------------------------------------------
    // wait_rd_cycles: 等待 N 个 RD 时钟周期
    // ------------------------------------------------------------------
    task wait_rd_cycles;
        input integer cycles;
        begin
            repeat(cycles) @(posedge i_rd_clk);
        end
    endtask

    // ------------------------------------------------------------------
    // reset_dut: 系统复位
    //   复位 ADC / RD 域信号, 置低 i_rst_n, 等待后释放
    // ------------------------------------------------------------------
    task reset_dut;
        begin
            $display("  [RESET] Asserting...");
            i_rst_n         <= 1'b0;
            i_wr_en         <= 1'b0;
            i_wr_data       <= 16'd0;
            i_pixel_type    <= 2'b00;
            i_frame_start   <= 1'b0;
            i_frame_end     <= 1'b0;
            i_image_width   <= 16'd0;
            i_image_height  <= 16'd0;
            i_read_mode     <= 2'd0;
            i_fifo_rd_en    <= 1'b0;
            last_img_width  <= 16'd0;
            last_img_height <= 16'd0;
            last_read_mode  <= 2'd0;

            wait_adc_cycles(5);
            wait_rd_cycles(5);
            i_rst_n <= 1'b1;
            wait_adc_cycles(10);
            wait_rd_cycles(10);
            $display("  [RESET] Released");
        end
    endtask

    // ------------------------------------------------------------------
    // wait_ddr3_init: 等待 DDR3 初始化完成
    // ------------------------------------------------------------------
    task wait_ddr3_init;
        begin
            $display("  [DDR3] Waiting for init_calib_complete...");
            while (!ddr3_init_done) begin
                @(posedge i_adcclk);
            end
            // 额外等待一段时间让 ui_clk 域稳定
            wait_adc_cycles(200);
            $display("  [DDR3] Init done");
        end
    endtask

    // ------------------------------------------------------------------
    // send_frame: 在 ADC 域发送一帧像素数据
    //   width       : image_width 值
    //   height      : image_height 值 (read_mode=0 时忽略)
    //   read_mode   : 0=仅宽度, 1=宽度×高度
    //   pixel_count : 实际发送的 active 像素数
    //   data_base   : 像素数据起始值 (每个像素递增 1)
    //
    //   协议:
    //     1. 设置 i_image_width / i_image_height / i_read_mode
    //     2. 脉冲 i_frame_start=1, 维持 1T, 然后拉低 (下降沿触发帧开始)
    //     3. 逐拍发送 active pixel (i_wr_en=1, i_pixel_type=2'b10)
    //     4. 脉冲 i_frame_end=1, 维持 1T, 然后拉低 (下降沿触发帧结束)
    //     5. 等待若干周期让 CDC 传播
    // ------------------------------------------------------------------
    task send_frame;
        input [15:0] width;
        input [15:0] height;
        input [1:0]  read_mode;
        input [15:0] pixel_count;
        input [15:0] data_base;
        input integer sb_idx;
        integer      p;
        begin
            $display("  [SEND] width=%0d, height=%0d, mode=%0d, pixels=%0d, base=0x%h",
                     width, height, read_mode, pixel_count, data_base);

            // 1. 设置帧参数
            @(posedge i_adcclk);
            i_image_width  <= width;
            i_image_height <= height;
            i_read_mode    <= read_mode;
            i_wr_en        <= 1'b0;
            i_wr_data      <= 16'd0;
            i_pixel_type   <= 2'b00;

            // 参数变化 → 顶层 (ccd_frame_buf_ddr) 自动软复位并重新锁定帧长度
            // 必须等待软复位完成再发帧, 否则 frame_start 会被复位吞掉
            if (width != last_img_width || height != last_img_height ||
                read_mode != last_read_mode) begin
                last_img_width  <= width;
                last_img_height <= height;
                last_read_mode  <= read_mode;
                wait_adc_cycles(2200);   // 覆盖 soft_rst (~41µs @100MHz ui_clk) + 三域同步
            end

            // 2. 脉冲 frame_start: 上升 → 保持 1T → 下降
            @(posedge i_adcclk);
            i_frame_start  <= 1'b1;  // frame_start_rise 在此触发
            @(posedge i_adcclk);
            i_frame_start  <= 1'b0;

            // 3. 发送 active pixels
            for (p = 0; p < pixel_count; p = p + 1) begin
                @(posedge i_adcclk);
                i_wr_en      <= 1'b1;
                i_pixel_type <= 2'b10;
                i_wr_data    <= data_base + p;
                scoreboard[sb_idx][p] <= data_base + p;
            end

            // 4. 最后一拍后拉低 wr_en, 脉冲 frame_end
            @(posedge i_adcclk);
            i_wr_en      <= 1'b0;
            i_pixel_type <= 2'b00;

            i_frame_end  <= 1'b1;  // frame_end_rise 在此触发
            @(posedge i_adcclk);
            i_frame_end  <= 1'b0;

            // 5. 等待帧处理完成 (CDC + controller 写状态机)
            //    等待足够长时间让所有 AXI 写事务完成
            wait_adc_cycles(100);
            $display("  [SEND] Done, %0d pixels sent", pixel_count);
        end
    endtask

    // ------------------------------------------------------------------
    // read_frame: 在 RD 域从 o_fifo_data 读取一帧, 并验证数据
    //   pixel_count : 期望的像素数
    //   data_base   : 期望的起始数据值
    //
    //   假设 rd-fifo 为标准模式 (1 拍流水线延迟):
    //     rd_en=1 → 下一拍 dout 有效
    //   读取流程:
    //     1. 等待 rd-fifo 中有数据 (检测 o_frame_num > 0)
    //     2. 断言 rd_en=1
    //     3. 等 1 拍流水线延迟
    //     4. 逐拍捕获 pixel_count 个数据并比对 scoreboard
    //     5. 检查 o_fifo_prelast 在倒数第2字时断言（下一字为最后一字）
    // ------------------------------------------------------------------
    task read_frame;
        input [15:0] pixel_count;
        input [15:0] data_base;
        input integer sb_idx;
        reg   [15:0] rd_data;
        integer      rd_cnt;
        integer      errors;
        begin
            $display("  [READ] Expecting %0d pixels, base=0x%h, sb_idx=%0d", pixel_count, data_base, sb_idx);
            rd_cnt   = 0;
            errors   = 0;

            // 等待 rd-fifo 中有数据
            wait_rd_cycles(10);

            @(posedge i_rd_clk);  // 流水线延迟拍
            i_fifo_rd_en <= 1'b1;
            @(posedge i_rd_clk);  // 流水线延迟拍

            // 逐拍读取
            while (rd_cnt < pixel_count) begin
                @(posedge i_rd_clk);
                rd_data = o_fifo_data;

                // 与 scoreboard 比对
                if (rd_data !== scoreboard[sb_idx][rd_cnt]) begin
                    $display("  [READ] ** MISMATCH ** idx=%0d: got=0x%h, expected=0x%h",
                             rd_cnt, rd_data, scoreboard[sb_idx][rd_cnt]);
                    errors = errors + 1;
                    $stop;
                end

                rd_cnt     = rd_cnt + 1;

                if(rd_cnt == pixel_count - 1)
                    i_fifo_rd_en <= 1'b0;
            end


            if (errors == 0)
                $display("  [READ] PASS — %0d pixels verified", pixel_count);
            else
                $display("  [READ] FAIL — %0d mismatch(es)", errors);

            wait_rd_cycles(5);
        end
    endtask

    // ------------------------------------------------------------------
    // read_frame_silent: 仅消费数据, 不自检 (用于清空 rd-fifo)
    // ------------------------------------------------------------------
    task read_frame_silent;
        input [15:0] pixel_count;
        integer      rd_cnt;
        begin
            rd_cnt = 0;
            wait_rd_cycles(10);

            // 断言 rd_en, 等 1 拍流水线
            i_fifo_rd_en <= 1'b1;
            @(posedge i_rd_clk);

            while (rd_cnt < pixel_count) begin
                @(posedge i_rd_clk);
                rd_cnt = rd_cnt + 1;
            end

            @(posedge i_rd_clk);
            i_fifo_rd_en <= 1'b0;
            wait_rd_cycles(5);
        end
    endtask

    // ------------------------------------------------------------------
    // wait_read_available: 等待 rd-fifo 中有数据可读
    //   timeout: 最大等待 ADC 周期数
    // ------------------------------------------------------------------
    task wait_read_available;
        input integer timeout;
        integer t;
        begin
            t = 0;
            while (o_frame_num == 0 && t < timeout) begin
                wait_adc_cycles(10);
                t = t + 10;
            end
            if (t >= timeout) begin
                $display("  [WAIT] Timeout waiting for read data");
                $stop;
            end
            else
                $display("  [WAIT] Data available, frames_in_ddr=%0d", o_frame_num);
        end
    endtask

    // ==================================================================
    // 测试序列
    // ==================================================================
    initial begin
        // ------------------------------------------------------------------
        // 初始状态
        // ------------------------------------------------------------------
        i_rst_n         = 1'b0;
        mig_rst_n        = 1'b0;   // MIG 复位 (仅上电时拉低一次)
        i_wr_en         = 1'b0;
        i_wr_data       = 16'd0;
        i_pixel_type    = 2'b00;
        i_frame_start   = 1'b0;
        i_frame_end     = 1'b0;
        i_image_width   = 16'd0;
        i_image_height  = 16'd0;
        i_read_mode     = 2'd0;
        i_fifo_rd_en    = 1'b0;
        test_num        = 8'd0;
        last_img_width  = 16'd0;
        last_img_height = 16'd0;
        last_read_mode  = 2'd0;

        wait_adc_cycles(10);
        wait_rd_cycles(10);

        $display("============================================================");
        $display("  test_ccd_frame_buf_ddr");
        $display("  MAX_FRAMES=%0d, MAX_FRAME_DEPTH=%0d", MAX_FRAMES, MAX_FRAME_DEPTH);
        $display("============================================================");

        // ================================================================
        // Test 1: 复位与 DDR3 初始化
        // ================================================================
        test_num = test_num + 1;
        $display("\n##########################################################");
        $display("  Test %0d: Reset & DDR3 Init", test_num);
        $display("##########################################################\n");
        reset_dut;
        mig_rst_n <= 1'b1;  // 释放 MIG 复位, 启动 DDR 校准
        wait_ddr3_init;
        $display("  o_frame_num = %0d (expect 0)", o_frame_num);

        // ================================================================
        // Test 2: 单帧含整 burst + 部分尾 (read_mode=0, 480 pixels = 1 full + 224 partial)
        //   注: 不选 512 以避开 wr-fifo 写侧实际深度 511 的边界
        // ================================================================
        test_num = test_num + 1;
        $display("\n##########################################################");
        $display("  Test %0d: Single frame — 1 full burst + partial tail (480 pixels)", test_num);
        $display("##########################################################\n");
        reset_dut;

        // 配置 read_mode=0, width=480: frame_depth = 480 pixels
        send_frame(16'd480, 16'd1, 2'd0, 16'd480, 16'hA000, 0);
        wait_read_available(50);
        read_frame(16'd480, 16'hA000, 0);

        $stop;

        // ================================================================
        // Test 3: 单帧含部分 burst 尾 (280 pixels = 1 full + 24 partial)
        // ================================================================
        test_num = test_num + 1;
        $display("\n##########################################################");
        $display("  Test %0d: Single frame — with partial tail (280 pixels)", test_num);
        $display("##########################################################\n");
        reset_dut;

        send_frame(16'd280, 16'd1, 2'd0, 16'd280, 16'hB000, 0);
        wait_read_available(50);
        read_frame(16'd280, 16'hB000, 0);

        $stop;

        // ================================================================
        // Test 4: 无效帧 — 像素计数不匹配 (announce 512, send only 500)
        //   预期: o_frame_exception 断言, 帧不计入
        // ================================================================
        test_num = test_num + 1;
        $display("\n##########################################################");
        $display("  Test %0d: Invalid frame — pixel count mismatch", test_num);
        $display("##########################################################\n");
        reset_dut;

        send_frame(16'd512, 16'd1, 2'd0, 16'd500, 16'hC000, 0);
        wait_adc_cycles(200);

        $stop;
        
        // ================================================================
        // Test 5: read_mode=1 (width × height), 60×8=480 pixels
        //   注: 不选 512 以避开 wr-fifo 写侧实际深度 511 的边界
        // ================================================================
        test_num = test_num + 1;
        $display("\n##########################################################");
        $display("  Test %0d: read_mode=1 — %0dx%0d=%0d pixels",
                 test_num, 60, 8, 60*8);
        $display("##########################################################\n");
        reset_dut;

        send_frame(16'd60, 16'd8, 2'd1, 16'd480, 16'hD000, 0);
        wait_read_available(50);
        read_frame(16'd480, 16'hD000, 0);

        $stop;
        
        // ================================================================
        // Test 6: 环形缓冲满 (MAX_FRAMES=4)
        //   写 4 帧 (填满), 验证第 5 帧被阻塞
        // ================================================================
        test_num = test_num + 1;
        $display("\n##########################################################");
        $display("  Test %0d: Ring buffer full (MAX_FRAMES=%0d)", test_num, MAX_FRAMES);
        $display("##########################################################\n");
        reset_dut;

        // 写 4 帧
        for (frame_i = 0; frame_i < MAX_FRAMES; frame_i = frame_i + 1) begin
            $display("  --- Writing frame %0d/%0d ---", frame_i + 1, MAX_FRAMES);
            send_frame(16'd256, 16'd1, 2'd0, 16'd256, 16'h1000 + frame_i * 16'h100, frame_i);
            $display("  frames_in_ddr (via o_frame_num) = %0d", o_frame_num);
        end

        // 尝试写第 5 帧 — 应被 wr_not_full 阻塞
        $display("  --- Attempting frame %0d (should be BLOCKED) ---", MAX_FRAMES + 1);
        // 注: wr_not_full 在 ui_clk 域判断, 帧开始前就会检查;
        //     如果缓冲满, controller 的 S_WR_IDLE→S_WR_WAIT 条件不满足,
        //     帧不会进入写状态机, wrfifo 中的像素不会被读出
        @(posedge i_adcclk);
        i_image_width  <= 16'd256;
        i_image_height <= 16'd1;
        i_read_mode    <= 2'd0;

        @(posedge i_adcclk);
        i_frame_start  <= 1'b1;  // frame_start_rise
        @(posedge i_adcclk);
        i_frame_start  <= 1'b0;

        // 发送 256 像素 (1 burst) — 但 controller 不会发起 AXI 写
        for (pixel_i = 0; pixel_i < 256; pixel_i = pixel_i + 1) begin
            @(posedge i_adcclk);
            i_wr_en      <= 1'b1;
            i_pixel_type <= 2'b10;
            i_wr_data    <= 16'hF000 + pixel_i;
        end
        @(posedge i_adcclk);
        i_wr_en      <= 1'b0;
        i_pixel_type <= 2'b00;

        i_frame_end  <= 1'b1;
        @(posedge i_adcclk);
        i_frame_end  <= 1'b0;

        wait_adc_cycles(500);
        $display("  After blocked frame: o_frame_num = %0d (expect %0d, no change)",
                 o_frame_num, MAX_FRAMES);
        $display("  o_frame_exception = %0d", o_frame_exception);

        // 清空: 读回 4 帧
        for (frame_i = 0; frame_i < MAX_FRAMES; frame_i = frame_i + 1) begin
            wait_read_available(50);
            read_frame(16'd256, 16'h1000 + frame_i * 16'h100, frame_i);
        end

        $stop;
        
        // ================================================================
        // Test 7: 读写同时进行
        //   写帧 0, 写帧 1 同时读帧 0
        // ================================================================
        test_num = test_num + 1;
        $display("\n##########################################################");
        $display("  Test %0d: Simultaneous write & read", test_num);
        $display("##########################################################\n");
        reset_dut;

        // 写帧 0
        send_frame(16'd256, 16'd1, 2'd0, 16'd256, 16'h2000, 0);
        // 写帧 1
        send_frame(16'd256, 16'd1, 2'd0, 16'd256, 16'h2100, 1);

        // 读帧 0
        wait_read_available(50);
        read_frame(16'd256, 16'h2000, 0);

        // 写帧 2 (在读帧 1 之前)
        send_frame(16'd256, 16'd1, 2'd0, 16'd256, 16'h2200, 2);

        // 读帧 1
        wait_read_available(50);
        read_frame(16'd256, 16'h2100, 1);

        // 读帧 2
        wait_read_available(50);
        read_frame(16'd256, 16'h2200, 2);

        $display("  o_frame_num = %0d (expect 0)", o_frame_num);

        $stop;
        
        // ================================================================
        // Test 8: 乒乓读写
        //   写 2 帧 → 读 1 帧 → 写 1 帧 → 读 2 帧
        //   验证帧计数在交替操作中保持正确
        // ================================================================
        test_num = test_num + 1;
        $display("\n##########################################################");
        $display("  Test %0d: Ping-pong read/write", test_num);
        $display("##########################################################\n");
        reset_dut;

        // 写 2 帧
        send_frame(16'd256, 16'd1, 2'd0, 16'd256, 16'h3000, 0);
        send_frame(16'd256, 16'd1, 2'd0, 16'd256, 16'h3100, 1);
        $display("  After 2 writes: o_frame_num = %0d", o_frame_num);

        // 读 1 帧
        wait_read_available(50);
        read_frame(16'd256, 16'h3000, 0);
        $display("  After 1 read:  o_frame_num = %0d", o_frame_num);

        // 写 1 帧
        send_frame(16'd256, 16'd1, 2'd0, 16'd256, 16'h3200, 2);
        $display("  After 1 write: o_frame_num = %0d", o_frame_num);

        // 读 2 帧
        wait_read_available(50);
        read_frame(16'd256, 16'h3100, 1);
        wait_read_available(50);
        read_frame(16'd256, 16'h3200, 2);
        $display("  After 2 reads: o_frame_num = %0d (expect 0)", o_frame_num);

        $stop;
        
        // ================================================================
        // Test 9: 最小帧 (恰好 1 burst = 256 pixels)
        // ================================================================
        test_num = test_num + 1;
        $display("\n##########################################################");
        $display("  Test %0d: Minimum frame — exactly 1 burst (256 pixels)", test_num);
        $display("##########################################################\n");
        reset_dut;

        send_frame(16'd256, 16'd1, 2'd0, 16'd256, 16'h4000, 0);
        wait_read_available(50);
        read_frame(16'd256, 16'h4000, 0);

        $stop;
     
        // ================================================================
        // Test 10: 大帧 (接近 MAX_FRAME_DEPTH, 2048 pixels = 8 bursts)
        // ================================================================
        test_num = test_num + 1;
        $display("\n##########################################################");
        $display("  Test %0d: Large frame — 2048 pixels (8 bursts)", test_num);
        $display("##########################################################\n");
        reset_dut;

        send_frame(16'd2048, 16'd1, 2'd0, 16'd2048, 16'h5000, 0);
        wait_read_available(50);
        read_frame(16'd2048, 16'h5000, 0);

        // ================================================================
        // 完成
        // ================================================================
        $display("\n============================================================");
        $display("  ALL TESTS COMPLETE");
        $display("============================================================");

        $finish;
    end

endmodule

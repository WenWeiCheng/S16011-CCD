`timescale 1ns / 1ps
//==============================================================================
// Module : test_ccd_ddr
// Desc   : ccd_ddr 顶层模块联合测试 (ccd_driver + ccd_frame_buf_ddr + ccd_frame_tx)
//
//   测试 1 : line binning 模式 — 触发一帧 → TX 发送 → Slave FIFO 读出验证
//   测试 2 : image 模式 — 触发一帧 → TX 发送 → Slave FIFO 读出验证
//   测试 3 : 乒乓双帧 — 连续触发两帧 → TX 发送两帧
//   测试 4 : exposure 打断 — 运行中拉高 exposure → 回到 IDLE
//==============================================================================
module test_ccd_ddr;

    // ==================================================================
    // 参数
    // ==================================================================
    parameter real SYS_CLK_PERIOD_NS      = 10.0;    // 100 MHz
    parameter real RD_CLK_PERIOD_NS       = 40.0;    // 25 MHz
    parameter real DDR3_CLK100_PERIOD_NS  = 10.0;    // 100 MHz
    parameter real DDR3_CLK200_PERIOD_NS  = 5.0;     // 200 MHz ref

    // ==================================================================
    // 系统
    // ==================================================================
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

    // ---- FX2 Slave FIFO 接口 ----
    reg         i_rd_clk;
    wire        i_rd_clk_n;
    reg         i_tx_frame_start;
    reg         i_slave_fifo_empty_n;
    reg         i_slave_fifo_full_n;
    wire [15:0] o_slave_fifo_data;
    wire        o_slave_fifo_data_valid_n;
    wire        o_slave_fifo_clk;
    wire        o_tx_last_n;
    wire [2:0]  o_frame_num;
    wire        o_frame_exception;

    // ---- MIG 接口 (ui_clk 域) ----
    wire        ui_clk;
    wire        ddr3_init_done;
    wire        mmcm_locked;
    wire        init_calib_complete;
    wire        ui_clk_sync_rst;

    // ---- MIG 时钟与复位 ----
    reg         mig_sys_clk;         // MIG sys_clk_i (100 MHz)
    reg         mig_clk_ref;         // MIG clk_ref_i (200 MHz)
    reg         mig_rst_n;           // MIG aresetn / sys_rst

    // ---- DDR3 物理接口 (MIG ↔ DDR3 model) ----
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

    // ---- AXI4 互连 (ccd_ddr M_AXI ↔ MIG S_AXI) ----
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
    // 写数据
    wire [127:0] axi_wdata;
    wire [15:0]  axi_wstrb;
    wire         axi_wlast;
    wire         axi_wvalid;
    wire         axi_wready;
    // 写响应
    wire [3:0]   axi_bid;
    wire [1:0]   axi_bresp;
    wire         axi_bvalid;
    wire         axi_bready;
    // 读地址
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
    // 读数据
    wire [3:0]   axi_rid;
    wire [127:0] axi_rdata;
    wire [1:0]   axi_rresp;
    wire         axi_rlast;
    wire         axi_rvalid;
    wire         axi_rready;

    // ---- 测试辅助 ----
    reg [3:0]  adc_cnt;
    reg [15:0] slave_rd_result;
    reg [15:0] wait_timeout;
    reg        frame_done_detected;

    // ==================================================================
    // DUT: ccd_ddr (CCD 控制器顶层)
    //   MIG 在 DUT 外部例化, 通过 AXI4 接口连接。
    // ==================================================================
    ccd_ddr #(
        .MAX_FRAME_DEPTH(2048),
        .MAX_FRAMES     (4)
    ) u_dut (
        .i_clk                   (i_clk),
        .i_rst_n                 (i_rst_n),
        .i_exposure              (i_exposure),
        .i_freq_sel              (i_freq_sel),
        .i_cdsclk_delay          (i_cdsclk_delay),
        .i_image_width           (i_image_width),
        .i_image_height          (i_image_height),
        .i_bevel_left            (i_bevel_left),
        .i_bevel_top             (i_bevel_top),
        .i_bevel_right           (i_bevel_right),
        .i_bevel_bottom          (i_bevel_bottom),
        .i_blank_left            (i_blank_left),
        .i_blank_right           (i_blank_right),
        .i_read_mode             (i_read_mode),
        .i_adc_data              (i_adc_data),
        .o_adcclk                (o_adcclk),
        .o_p1v                   (o_p1v),
        .o_p2v_tg                (o_p2v_tg),
        .o_p1h                   (o_p1h),
        .o_p2h                   (o_p2h),
        .o_p3h                   (o_p3h),
        .o_p4h_sg                (o_p4h_sg),
        .o_rg                    (o_rg),
        .o_cdsclk1               (o_cdsclk1),
        .o_cdsclk2               (o_cdsclk2),
        .i_rd_clk                (i_rd_clk),
        .i_rd_clk_n              (i_rd_clk_n),
        .o_slave_fifo_clk        (o_slave_fifo_clk),
        .i_tx_frame_start        (i_tx_frame_start),
        .i_slave_fifo_empty_n    (i_slave_fifo_empty_n),
        .i_slave_fifo_full_n     (i_slave_fifo_full_n),
        .o_slave_fifo_data       (o_slave_fifo_data),
        .o_slave_fifo_data_valid_n(o_slave_fifo_data_valid_n),
        .o_tx_last_n          (o_tx_last_n),
        .o_frame_num             (o_frame_num),
        .o_frame_exception       (o_frame_exception),
        .i_ui_clk                (ui_clk),
        .i_mmcm_locked           (mmcm_locked),
        .i_init_calib_complete   (init_calib_complete),
        .M_AXI_AWID              (axi_awid),
        .M_AXI_AWADDR            (axi_awaddr),
        .M_AXI_AWLEN             (axi_awlen),
        .M_AXI_AWSIZE            (axi_awsize),
        .M_AXI_AWBURST           (axi_awburst),
        .M_AXI_AWLOCK            (axi_awlock),
        .M_AXI_AWCACHE           (axi_awcache),
        .M_AXI_AWPROT            (axi_awprot),
        .M_AXI_AWQOS             (axi_awqos),
        .M_AXI_AWREGION          (),
        .M_AXI_AWVALID           (axi_awvalid),
        .M_AXI_AWREADY           (axi_awready),
        .M_AXI_WDATA             (axi_wdata),
        .M_AXI_WSTRB             (axi_wstrb),
        .M_AXI_WLAST             (axi_wlast),
        .M_AXI_WVALID            (axi_wvalid),
        .M_AXI_WREADY            (axi_wready),
        .M_AXI_BID               (axi_bid),
        .M_AXI_BRESP             (axi_bresp),
        .M_AXI_BVALID            (axi_bvalid),
        .M_AXI_BREADY            (axi_bready),
        .M_AXI_ARID              (axi_arid),
        .M_AXI_ARADDR            (axi_araddr),
        .M_AXI_ARLEN             (axi_arlen),
        .M_AXI_ARSIZE            (axi_arsize),
        .M_AXI_ARBURST           (axi_arburst),
        .M_AXI_ARLOCK            (axi_arlock),
        .M_AXI_ARCACHE           (axi_arcache),
        .M_AXI_ARPROT            (axi_arprot),
        .M_AXI_ARQOS             (axi_arqos),
        .M_AXI_ARREGION          (),
        .M_AXI_ARVALID           (axi_arvalid),
        .M_AXI_ARREADY           (axi_arready),
        .M_AXI_RID               (axi_rid),
        .M_AXI_RDATA             (axi_rdata),
        .M_AXI_RRESP             (axi_rresp),
        .M_AXI_RLAST             (axi_rlast),
        .M_AXI_RVALID            (axi_rvalid),
        .M_AXI_RREADY            (axi_rready)
    );

    // ==================================================================
    // MIG 7-Series DDR3 Controller (外部例化)
    //   连接 ccd_ddr 的 AXI4 Master ↔ MIG S_AXI ↔ DDR3 仿真模型
    // ==================================================================
    assign i_rd_clk_n = ~i_rd_clk;
    assign ddr3_init_done = mmcm_locked && init_calib_complete;

    mig_7series_0 u_mig (
        // DDR3 physical
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
        // Clocks
        .sys_clk_i            (mig_sys_clk),
        .clk_ref_i            (mig_clk_ref),
        .ui_clk               (ui_clk),
        .ui_clk_sync_rst      (ui_clk_sync_rst),
        .mmcm_locked          (mmcm_locked),
        // Reset
        .aresetn              (mig_rst_n),
        .sys_rst              (mig_rst_n),
        // Application interface ports
        .app_sr_req           (1'b0),
        .app_ref_req          (1'b0),
        .app_zq_req           (1'b0),
        .app_sr_active        (),
        .app_ref_ack          (),
        .app_zq_ack           (),
        // AXI write address
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
        // AXI write data
        .s_axi_wdata          (axi_wdata),
        .s_axi_wstrb          (axi_wstrb),
        .s_axi_wlast          (axi_wlast),
        .s_axi_wvalid         (axi_wvalid),
        .s_axi_wready         (axi_wready),
        // AXI write response
        .s_axi_bready         (axi_bready),
        .s_axi_bid            (axi_bid),
        .s_axi_bresp          (axi_bresp),
        .s_axi_bvalid         (axi_bvalid),
        // AXI read address
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
        // AXI read data
        .s_axi_rready         (axi_rready),
        .s_axi_rid            (axi_rid),
        .s_axi_rdata          (axi_rdata),
        .s_axi_rresp          (axi_rresp),
        .s_axi_rlast          (axi_rlast),
        .s_axi_rvalid         (axi_rvalid)
    );

    // ==================================================================
    // DDR3 仿真模型 × 2 — 32-bit DDR3 拆为 2 个 16-bit 模型
    //   model_hi: dq[31:16], dqs[3:2], dm[3:2]
    //   model_lo: dq[15:0],  dqs[1:0], dm[1:0]
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
    // 时钟生成
    // ==================================================================
    initial i_clk = 1'b0;
    always #(SYS_CLK_PERIOD_NS / 2.0) i_clk = ~i_clk;

    initial i_rd_clk = 1'b0;
    always #(RD_CLK_PERIOD_NS / 2.0) i_rd_clk = ~i_rd_clk;

    initial mig_sys_clk = 1'b0;
    always #(DDR3_CLK100_PERIOD_NS / 2.0) mig_sys_clk = ~mig_sys_clk;

    initial mig_clk_ref = 1'b0;
    always #(DDR3_CLK200_PERIOD_NS / 2.0) mig_clk_ref = ~mig_clk_ref;

    // ==================================================================
    // ADC 数据驱动
    //   模拟 ADC 在 ADCCLK 上升/下降沿交替输出 8bit 数据。
    //   高字节 = {adc_cnt, 4'hA}, 低字节 = {adc_cnt, 4'h5}
    //   → o_pixel_data = {adc_cnt_rise, 4'hA, adc_cnt_fall, 4'h5}
    // ==================================================================
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

    // ---- 等待系统时钟周期 ----
    task sys_wait(input integer cycles);
        begin
            repeat (cycles) @(posedge i_clk);
        end
    endtask

    // ---- 等待 DDR3 校准完成 ----
    task wait_ddr3_init;
        begin
            $display("  [DDR3] Waiting for init_calib_complete...");
            while (!ddr3_init_done) begin
                @(posedge i_clk);
            end
            sys_wait(2000);
            $display("  [DDR3] Init done");
        end
    endtask

    // ---- 等待帧缓存中有数据可读 (o_frame_num > 0) ----
    task wait_frame_available;
        input integer timeout_us;
        integer t;
        begin
            t = 0;
            while (o_frame_num == 0 && t < timeout_us) begin
                #1000;  // 1us step
                t = t + 1;
            end
            if (t >= timeout_us) begin
                $display("  [WAIT] Timeout: no frame available after %0d us", timeout_us);
                $stop;
            end
            else
                $display("  [WAIT] Frame available, o_frame_num=%0d", o_frame_num);
        end
    endtask

    // ---- 从 Slave FIFO 读取一字 (等待 valid_n=0 后采样) ----
    task slave_read_word;
        begin
            @(negedge i_rd_clk);
            while (o_slave_fifo_data_valid_n !== 1'b0)
                @(negedge i_rd_clk);
            slave_rd_result = o_slave_fifo_data;
        end
    endtask

    // ---- 从 Slave FIFO 读出 N 个字 ----
    task slave_read_words(input integer num);
        integer k;
        begin
            for (k = 0; k < num; k = k + 1)
                slave_read_word;
        end
    endtask

    // ---- 触发帧发送 (下降沿) ----
    task send_frame;
        begin
            @(posedge i_rd_clk);
            i_tx_frame_start <= 1'b1;
            @(posedge i_rd_clk);
            i_tx_frame_start <= 1'b0;
        end
    endtask

    // ---- 等待 frame_done (最多等 2000 rd_clk, DDR 版本需更长时间) ----
    task wait_frame_done;
        begin
            wait_timeout = 0;
            while (o_tx_last_n !== 1'b0 && wait_timeout < 2000) begin
                @(posedge i_rd_clk);
                wait_timeout = wait_timeout + 1;
            end
            if (wait_timeout >= 2000) begin
                $display("  [WAIT] Timeout: no frame send complete after %0d us", 2000);
                $stop;
            end
            frame_done_detected = (o_tx_last_n === 1'b0);
        end
    endtask

    // ---- 等待 CDC 稳定 ----
    task wait_cdc;
        begin
            rd_wait(20);
        end
    endtask

    // ---- 等待 CCD 系统稳定 (DDR 传输完成需要时间) ----
    task wait_ddr_cdc;
        begin
            rd_wait(50);
            sys_wait(50);
        end
    endtask

    // ==================================================================
    // 主激励
    // ==================================================================
    initial begin : stimulus

        // ---- 初始化 ----
        i_freq_sel           = 1'b0;        // 100kHz SCLK
        i_rst_n              = 1'b0;
        mig_rst_n             = 1'b0;        // MIG 上电复位
        i_exposure           = 1'b1;
        i_image_width        = 16'd8;
        i_image_height       = 16'd2;
        i_bevel_left         = 4'd1;
        i_bevel_top          = 4'd1;
        i_bevel_right        = 4'd1;
        i_bevel_bottom       = 4'd1;
        i_blank_left         = 4'd1;
        i_blank_right        = 4'd1;
        i_read_mode          = 2'd0;        // line binning
        i_adc_data           = 8'd0;
        i_cdsclk_delay       = 7'd0;
        i_tx_frame_start     = 1'b1;        // 默认高, 下降沿触发
        i_slave_fifo_empty_n = 1'b1;        // Slave FIFO 非空 (可接收)
        i_slave_fifo_full_n  = 1'b1;        // Slave FIFO 未满 (可写入)
        adc_cnt              = 4'd0;

        $display("============================================================");
        $display("  test_ccd_ddr");
        $display("============================================================");

        // ---- 释放系统复位, 然后释放 MIG 复位 ----
        sys_wait(50);
        i_rst_n = 1'b1;
        sys_wait(100);
        mig_rst_n = 1'b1;

        // ---- 等待 DDR3 校准完成 ----
        wait_ddr3_init;

        // ================================================================
        // 测试 1: line binning 模式 — 单帧写入 + TX 发送 + Slave FIFO 读出
        //   v=4, h=8, l=1, frame_depth = 4 active 像素
        // ================================================================
        $display("========================================");
        $display("[TEST 1] line binning: single frame");
        $display("========================================");
        i_read_mode = 2'd0;

        // 触发 exposure 下降沿
        @(negedge i_clk);
        i_exposure = 1'b0;

        // 等待一帧完成 (v=4 + h≈14 = ~18 SCLK ≈ 180us, 多等一些)
        wait_us(300);

        // 拉高 exposure, 回到 IDLE
        i_exposure = 1'b1;

        // 等待 DDR3 写入完成 + CDC 稳定
        wait_ddr_cdc;

        // 等待帧缓存中有数据
        wait_frame_available(500);

        // 触发帧发送, 同时读取数据 (tx 在后台流水输出)
        $display("  Triggering TX...");
        send_frame;
        // 在 TX 传输过程中从 Slave FIFO 读取数据
        slave_read_words(8);
        wait_frame_done;
        if (frame_done_detected)
            $display("[PASS] frame_done received, last=0x%04h", slave_rd_result);
        else
            $display("[FAIL] frame_done timeout");
        wait_cdc;

        $stop;

        // ================================================================
        // 测试 2: image 模式 — 单帧写入 + TX 发送 + Slave FIFO 读出
        //   bevel_top/bottom=0, 使 frame_depth = image_width * image_height
        //   v=1, h=8, l=2, frame_depth = 4*2 = 8 active 像素
        // ================================================================
        $display("========================================");
        $display("[TEST 2] image mode: single frame");
        $display("========================================");
        i_read_mode    = 2'd1;
        i_bevel_top    = 4'd0;
        i_bevel_bottom = 4'd0;

        @(negedge i_clk);
        i_exposure = 1'b0;

        // 等待一帧完成 (l*(v+h) ≈ 2*15 = 30 SCLK ≈ 300us)
        wait_us(400);

        i_exposure = 1'b1;
        wait_ddr_cdc;
        wait_frame_available(500);

        // 触发帧发送, 同时读取数据
        $display("  Triggering TX...");
        send_frame;
        slave_read_words(8);
        wait_frame_done;
        if (frame_done_detected)
            $display("[PASS] frame_done received, last=0x%04h", slave_rd_result);
        else
            $display("[FAIL] frame_done timeout");
        wait_cdc;

        $stop;

        // ================================================================
        // 测试 3: 乒乓双帧 — 连续两帧 → TX 发送两帧
        //   用 line binning 模式 (帧短, 仿真快)
        // ================================================================
        $display("========================================");
        $display("[TEST 3] Ping-pong: 2 frames");
        $display("========================================");
        i_read_mode = 2'd0;

        // 帧 1
        @(negedge i_clk);
        i_exposure = 1'b0;
        wait_us(300);
        i_exposure = 1'b1;
        wait_us(100);

        // 帧 2
        @(negedge i_clk);
        i_exposure = 1'b0;
        wait_us(500);
        i_exposure = 1'b1;
        wait_ddr_cdc;

        // 发送并读出帧 1 (读数据与 TX 流水线同时进行)
        wait_frame_available(500);
        $display("  Sending frame 1...");
        send_frame;
        slave_read_words(8);
        wait_frame_done;
        $display("  Frame 1 done");

        // 发送并读出帧 2
        wait_frame_available(500);
        $display("  Sending frame 2...");
        send_frame;
        slave_read_words(8);
        wait_frame_done;
        $display("  Frame 2 done");

        wait_cdc;

        $stop;

        // ================================================================
        // 测试 4: exposure 打断 — 运行中拉高, 验证回到 IDLE
        // ================================================================
        $display("========================================");
        $display("[TEST 4] Exposure abort");
        $display("========================================");
        @(negedge i_clk);
        i_exposure = 1'b0;
        wait_us(80);                 // 约 8 SCLK, 应在 HORIZONTAL 阶段内
        @(negedge i_clk);
        i_exposure = 1'b1;           // 打断
        wait_us(100);

        $display("============================================================");
        $display("  ALL TESTS COMPLETE");
        $display("============================================================");

        $finish;
    end

endmodule

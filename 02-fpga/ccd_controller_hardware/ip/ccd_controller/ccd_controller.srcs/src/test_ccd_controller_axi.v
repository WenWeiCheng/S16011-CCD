`timescale 1ns / 1ps
//==============================================================================
// Module : test_ccd_controller_axi
// Desc   : ccd_controller_v1_0 AXI4-Lite 外设联合测试。
//          通过 AXI-Lite Master BFM 配置寄存器，驱动 CCD 采集 + DDR3 帧缓存
//          + FX2 帧发送，验证寄存器读写、中断状态。
//
//   测试 1 : 寄存器读写 — 写 CTRL/IMG_SIZE/BEVEL_BLANK → 读回验证
//   测试 2 : line binning + TRIGGER 触发帧发送 → Slave FIFO 读出
//   测试 3 : 中断 — 使能 tx_done IRQ → 发送帧 → 验证 intr 拉高
//   测试 4 : STATUS 实时读取 — 读取 frame_num / ddr3_init_done
//==============================================================================
module test_ccd_controller_axi;

    // ==================================================================
    // 参数
    // ==================================================================
    parameter real AXI_CLK_PERIOD_NS       = 10.0;    // 100 MHz
    parameter real RD_CLK_PERIOD_NS        = 40.0;    // 25 MHz
    parameter real DDR3_CLK100_PERIOD_NS   = 10.0;    // 100 MHz
    parameter real DDR3_CLK200_PERIOD_NS   = 5.0;     // 200 MHz

    // ---- 寄存器地址 (字节偏移) ----
    parameter [5:0] ADDR_CTRL        = 6'h00;
    parameter [5:0] ADDR_IMG_SIZE    = 6'h04;
    parameter [5:0] ADDR_BEVEL_BLANK = 6'h08;
    parameter [5:0] ADDR_TRIGGER     = 6'h0C;
    parameter [5:0] ADDR_STATUS      = 6'h10;
    parameter [5:0] ADDR_INTR_EN     = 6'h14;
    parameter [5:0] ADDR_INTR_STS    = 6'h18;

    // ---- STATUS 位掩码 ----
    parameter [31:0] STS_DDR3_DONE   = 32'h00010000;  // [16]
    parameter [31:0] STS_EXCEP_CNT   = 32'h0000FE00;  // [15:9]
    parameter [31:0] STS_EXCEPTION   = 32'h00000100;  // [8]
    parameter [31:0] STS_FRAME_NUM   = 32'h000000FF;  // [7:0]

    // ---- INTR 位掩码 ----
    parameter [31:0] INTR_TX_DONE    = 32'h00000200;  // EN[9] / STS[9]
    parameter [31:0] INTR_EXCEPTION  = 32'h00000100;  // EN[8]

    // ==================================================================
    // 系统 — AXI 域 (s00_axi_aclk = ccd_ddr.i_ccd_clk)
    // ==================================================================
    reg         s00_axi_aclk;
    reg         s00_axi_aresetn;

    // ---- AXI4-Lite 主机信号 ----
    reg  [5:0]  axi_awaddr;
    reg  [2:0]  axi_awprot;
    reg         axi_awvalid;
    wire        axi_awready;
    reg  [31:0] axi_wdata;
    reg  [3:0]  axi_wstrb;
    reg         axi_wvalid;
    wire        axi_wready;
    wire [1:0]  axi_bresp;
    wire        axi_bvalid;
    reg         axi_bready;
    reg  [5:0]  axi_araddr;
    reg  [2:0]  axi_arprot;
    reg         axi_arvalid;
    wire        axi_arready;
    wire [31:0] axi_rdata;
    wire [1:0]  axi_rresp;
    wire        axi_rvalid;
    reg         axi_rready;

    // ---- CCD 驱动信号 ----
    wire o_adcclk;
    wire o_p1v, o_p2v_tg, o_p1h, o_p2h, o_p3h, o_p4h_sg, o_rg;
    wire o_cdsclk1, o_cdsclk2;

    // ---- ADC 数据 ----
    reg  [7:0]  i_adc_data;

    // ---- FX2 Slave FIFO ----
    reg         i_rd_clk;
    wire        i_rd_clk_n;       // 读时钟反相 (ccd_frame_tx 内部边沿采样用)
    wire        o_slave_fifo_clk; // 读时钟扇出 (i_rd_clk)
    reg         i_slave_fifo_empty_n;
    reg         i_slave_fifo_full_n;
    wire [15:0] o_slave_fifo_data;
    wire        o_slave_fifo_data_wr_en_n;
    wire        o_slave_fifo_data_last_n;

    // ---- 中断 ----
    wire        intr;

    // ---- MIG / DDR3 ----
    wire        ui_clk;
    wire        ddr3_init_done;
    wire        mmcm_locked;
    wire        init_calib_complete;

    // ---- MIG 时钟 ----
    reg         mig_sys_clk;
    reg         mig_clk_ref;
    reg         mig_rst_n;

    // ---- DDR3 物理接口 ----
    wire [31:0]  ddr3_dq;
    wire [3:0]   ddr3_dqs_n, ddr3_dqs_p;
    wire [14:0]  ddr3_addr;
    wire [2:0]   ddr3_ba;
    wire         ddr3_ras_n, ddr3_cas_n, ddr3_we_n, ddr3_reset_n;
    wire [0:0]   ddr3_ck_p, ddr3_ck_n, ddr3_cke, ddr3_cs_n, ddr3_odt;
    wire [3:0]   ddr3_dm;

    // ---- AXI4 Master 互连 ----
    wire [3:0]   m_axi_awid;
    wire [29:0]  m_axi_awaddr;
    wire [7:0]   m_axi_awlen;
    wire [2:0]   m_axi_awsize;
    wire [1:0]   m_axi_awburst;
    wire         m_axi_awlock, m_axi_awvalid, m_axi_awready;
    wire [3:0]   m_axi_awcache, m_axi_awqos, m_axi_awregion;
    wire [2:0]   m_axi_awprot;
    wire [127:0] m_axi_wdata;
    wire [15:0]  m_axi_wstrb;
    wire         m_axi_wlast, m_axi_wvalid, m_axi_wready;
    wire [3:0]   m_axi_bid;
    wire [1:0]   m_axi_bresp;
    wire         m_axi_bvalid, m_axi_bready;
    wire [3:0]   m_axi_arid;
    wire [29:0]  m_axi_araddr;
    wire [7:0]   m_axi_arlen;
    wire [2:0]   m_axi_arsize;
    wire [1:0]   m_axi_arburst;
    wire         m_axi_arlock, m_axi_arvalid, m_axi_arready;
    wire [3:0]   m_axi_arcache, m_axi_arqos, m_axi_arregion;
    wire [2:0]   m_axi_arprot;
    wire [3:0]   m_axi_rid;
    wire [127:0] m_axi_rdata;
    wire [1:0]   m_axi_rresp;
    wire         m_axi_rlast, m_axi_rvalid, m_axi_rready;

    // ---- 测试辅助 ----
    reg [3:0]   test_num;
    reg [3:0]   adc_cnt;
    reg [15:0]  slave_rd_result;
    reg [15:0]  wait_timeout;
    reg [31:0]  rd_data;
    reg [31:0]  axi_read_dbval;

    // ==================================================================
    // DUT: ccd_controller_v1_0 (AXI4-Lite 外设)
    // ==================================================================
    ccd_controller_v1_0 #(
        .MAX_FRAME_DEPTH(2048),
        .MAX_FRAMES     (4)
    ) u_dut (
        // AXI4-Lite Slave
        .s00_axi_aclk    (s00_axi_aclk),
        .s00_axi_aresetn (s00_axi_aresetn),
        .s00_axi_awaddr  (axi_awaddr),
        .s00_axi_awprot  (axi_awprot),
        .s00_axi_awvalid (axi_awvalid),
        .s00_axi_awready (axi_awready),
        .s00_axi_wdata   (axi_wdata),
        .s00_axi_wstrb   (axi_wstrb),
        .s00_axi_wvalid  (axi_wvalid),
        .s00_axi_wready  (axi_wready),
        .s00_axi_bresp   (axi_bresp),
        .s00_axi_bvalid  (axi_bvalid),
        .s00_axi_bready  (axi_bready),
        .s00_axi_araddr  (axi_araddr),
        .s00_axi_arprot  (axi_arprot),
        .s00_axi_arvalid (axi_arvalid),
        .s00_axi_arready (axi_arready),
        .s00_axi_rdata   (axi_rdata),
        .s00_axi_rresp   (axi_rresp),
        .s00_axi_rvalid  (axi_rvalid),
        .s00_axi_rready  (axi_rready),
        // 用户端口
        .intr            (intr),
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
        .i_adc_data      (i_adc_data),
        .i_rd_clk        (i_rd_clk),
        .i_rd_clk_n      (i_rd_clk_n),
        .i_slave_fifo_empty_n(i_slave_fifo_empty_n),
        .i_slave_fifo_full_n (i_slave_fifo_full_n),
        .o_slave_fifo_data    (o_slave_fifo_data),
        .o_slave_fifo_data_wr_en_n(o_slave_fifo_data_wr_en_n),
        .o_slave_fifo_data_last_n (o_slave_fifo_data_last_n),
        .o_slave_fifo_clk   (o_slave_fifo_clk),
        .i_ui_clk        (ui_clk),
        .i_mmcm_locked   (mmcm_locked),
        .i_init_calib_complete(init_calib_complete),
        // AXI4 Master → MIG
        .M_AXI_AWID      (m_axi_awid),
        .M_AXI_AWADDR    (m_axi_awaddr),
        .M_AXI_AWLEN     (m_axi_awlen),
        .M_AXI_AWSIZE    (m_axi_awsize),
        .M_AXI_AWBURST   (m_axi_awburst),
        .M_AXI_AWLOCK    (m_axi_awlock),
        .M_AXI_AWCACHE   (m_axi_awcache),
        .M_AXI_AWPROT    (m_axi_awprot),
        .M_AXI_AWQOS     (m_axi_awqos),
        .M_AXI_AWREGION  (m_axi_awregion),
        .M_AXI_AWVALID   (m_axi_awvalid),
        .M_AXI_AWREADY   (m_axi_awready),
        .M_AXI_WDATA     (m_axi_wdata),
        .M_AXI_WSTRB     (m_axi_wstrb),
        .M_AXI_WLAST     (m_axi_wlast),
        .M_AXI_WVALID    (m_axi_wvalid),
        .M_AXI_WREADY    (m_axi_wready),
        .M_AXI_BID       (m_axi_bid),
        .M_AXI_BRESP     (m_axi_bresp),
        .M_AXI_BVALID    (m_axi_bvalid),
        .M_AXI_BREADY    (m_axi_bready),
        .M_AXI_ARID      (m_axi_arid),
        .M_AXI_ARADDR    (m_axi_araddr),
        .M_AXI_ARLEN     (m_axi_arlen),
        .M_AXI_ARSIZE    (m_axi_arsize),
        .M_AXI_ARBURST   (m_axi_arburst),
        .M_AXI_ARLOCK    (m_axi_arlock),
        .M_AXI_ARCACHE   (m_axi_arcache),
        .M_AXI_ARPROT    (m_axi_arprot),
        .M_AXI_ARQOS     (m_axi_arqos),
        .M_AXI_ARREGION  (m_axi_arregion),
        .M_AXI_ARVALID   (m_axi_arvalid),
        .M_AXI_ARREADY   (m_axi_arready),
        .M_AXI_RID       (m_axi_rid),
        .M_AXI_RDATA     (m_axi_rdata),
        .M_AXI_RRESP     (m_axi_rresp),
        .M_AXI_RLAST     (m_axi_rlast),
        .M_AXI_RVALID    (m_axi_rvalid),
        .M_AXI_RREADY    (m_axi_rready)
    );

    // ==================================================================
    // MIG 7-Series DDR3 Controller
    // ==================================================================
    assign ddr3_init_done = mmcm_locked && init_calib_complete;

    mig_7series_0 u_mig (
        .ddr3_dq             (ddr3_dq),
        .ddr3_dqs_n          (ddr3_dqs_n),
        .ddr3_dqs_p          (ddr3_dqs_p),
        .ddr3_addr           (ddr3_addr),
        .ddr3_ba             (ddr3_ba),
        .ddr3_ras_n          (ddr3_ras_n),
        .ddr3_cas_n          (ddr3_cas_n),
        .ddr3_we_n           (ddr3_we_n),
        .ddr3_reset_n        (ddr3_reset_n),
        .ddr3_ck_p           (ddr3_ck_p),
        .ddr3_ck_n           (ddr3_ck_n),
        .ddr3_cke            (ddr3_cke),
        .ddr3_cs_n           (ddr3_cs_n),
        .ddr3_dm             (ddr3_dm),
        .ddr3_odt            (ddr3_odt),
        .init_calib_complete (init_calib_complete),
        .sys_clk_i           (mig_sys_clk),
        .clk_ref_i           (mig_clk_ref),
        .ui_clk              (ui_clk),
        .ui_clk_sync_rst     (),
        .mmcm_locked         (mmcm_locked),
        .aresetn             (mig_rst_n),
        .sys_rst             (mig_rst_n),
        .app_sr_req          (1'b0),
        .app_ref_req         (1'b0),
        .app_zq_req          (1'b0),
        .app_sr_active       (),
        .app_ref_ack         (),
        .app_zq_ack          (),
        .s_axi_awid          (m_axi_awid),
        .s_axi_awaddr        (m_axi_awaddr),
        .s_axi_awlen         (m_axi_awlen),
        .s_axi_awsize        (m_axi_awsize),
        .s_axi_awburst       (m_axi_awburst),
        .s_axi_awlock        (m_axi_awlock),
        .s_axi_awcache       (m_axi_awcache),
        .s_axi_awprot        (m_axi_awprot),
        .s_axi_awqos         (m_axi_awqos),
        .s_axi_awvalid       (m_axi_awvalid),
        .s_axi_awready       (m_axi_awready),
        .s_axi_wdata         (m_axi_wdata),
        .s_axi_wstrb         (m_axi_wstrb),
        .s_axi_wlast         (m_axi_wlast),
        .s_axi_wvalid        (m_axi_wvalid),
        .s_axi_wready        (m_axi_wready),
        .s_axi_bready        (m_axi_bready),
        .s_axi_bid           (m_axi_bid),
        .s_axi_bresp         (m_axi_bresp),
        .s_axi_bvalid        (m_axi_bvalid),
        .s_axi_arid          (m_axi_arid),
        .s_axi_araddr        (m_axi_araddr),
        .s_axi_arlen         (m_axi_arlen),
        .s_axi_arsize        (m_axi_arsize),
        .s_axi_arburst       (m_axi_arburst),
        .s_axi_arlock        (m_axi_arlock),
        .s_axi_arcache       (m_axi_arcache),
        .s_axi_arprot        (m_axi_arprot),
        .s_axi_arqos         (m_axi_arqos),
        .s_axi_arvalid       (m_axi_arvalid),
        .s_axi_arready       (m_axi_arready),
        .s_axi_rready        (m_axi_rready),
        .s_axi_rid           (m_axi_rid),
        .s_axi_rdata         (m_axi_rdata),
        .s_axi_rresp         (m_axi_rresp),
        .s_axi_rlast         (m_axi_rlast),
        .s_axi_rvalid        (m_axi_rvalid)
    );

    // ==================================================================
    // DDR3 仿真模型 × 2
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
    initial s00_axi_aclk = 1'b0;
    always #(AXI_CLK_PERIOD_NS / 2.0) s00_axi_aclk = ~s00_axi_aclk;

    initial i_rd_clk = 1'b0;
    always #(RD_CLK_PERIOD_NS / 2.0) i_rd_clk = ~i_rd_clk;
    assign i_rd_clk_n = ~i_rd_clk;

    initial mig_sys_clk = 1'b0;
    always #(DDR3_CLK100_PERIOD_NS / 2.0) mig_sys_clk = ~mig_sys_clk;

    initial mig_clk_ref = 1'b0;
    always #(DDR3_CLK200_PERIOD_NS / 2.0) mig_clk_ref = ~mig_clk_ref;

    // ==================================================================
    // ADC 数据驱动
    // ==================================================================
    always @(posedge o_adcclk) begin
        adc_cnt    <= adc_cnt + 1'b1;
        i_adc_data <= {adc_cnt, 4'hA};
    end
    always @(negedge o_adcclk) begin
        i_adc_data <= {adc_cnt, 4'h5};
    end

    // ==================================================================
    // AXI4-Lite Master BFM
    // ==================================================================

    // ---- AXI 单次写 (AXI4-Lite, 1 周期延迟) ----
    task axi_write;
        input [5:0]  addr;
        input [31:0] data;
        begin
            @(posedge s00_axi_aclk);
            axi_awaddr  <= addr;
            axi_awvalid <= 1'b1;
            axi_wdata   <= data;
            axi_wstrb   <= 4'hF;
            axi_wvalid  <= 1'b1;
            axi_bready  <= 1'b1;
            // 等待 AWREADY & WREADY (同周期)
            @(posedge s00_axi_aclk);
            while (!(axi_awready && axi_wready))
                @(posedge s00_axi_aclk);
            // 地址/数据已接收
            axi_awaddr  <= 6'h0;
            axi_awvalid <= 1'b0;
            axi_wdata   <= 32'h0;
            axi_wstrb   <= 4'h0;
            axi_wvalid  <= 1'b0;
            // 等待 BVALID
            while (!axi_bvalid)
                @(posedge s00_axi_aclk);
            // 握手完成
            axi_bready  <= 1'b0;
            @(posedge s00_axi_aclk);
        end
    endtask

    // ---- AXI 单次读 ----
    task axi_read;
        input  [5:0]  addr;
        output [31:0] data;
        begin
            @(posedge s00_axi_aclk);
            axi_araddr  <= addr;
            axi_arvalid <= 1'b1;
            axi_rready  <= 1'b1;
            // 等待 ARREADY
            while (!axi_arready)
                @(posedge s00_axi_aclk);
            axi_araddr  <= 6'h0;
            axi_arvalid <= 1'b0;
            // 等待 RVALID
            while (!axi_rvalid)
                @(posedge s00_axi_aclk);
            data = axi_rdata;
            axi_rready <= 1'b0;
            @(posedge s00_axi_aclk);
        end
    endtask

    // ---- AXI 读并打印 ----
    task axi_read_dbg;
        input [5:0]   addr;
        input [255:0] name;
        begin
            axi_read(addr, axi_read_dbval);
            $display("  [AXI-RD] %0s (0x%02h) = 0x%08h", name, addr, axi_read_dbval);
        end
    endtask

    // ==================================================================
    // 辅助任务
    // ==================================================================
    task wait_us;
        input integer us;
        begin
            #(us * 1000);
        end
    endtask

    task rd_wait;
        input integer cycles;
        begin
            repeat (cycles) @(posedge i_rd_clk);
        end
    endtask

    task sys_wait;
        input integer cycles;
        begin
            repeat (cycles) @(posedge s00_axi_aclk);
        end
    endtask

    task wait_ddr3_init;
        begin
            $display("  [DDR3] Waiting for init_calib_complete...");
            while (!ddr3_init_done)
                @(posedge s00_axi_aclk);
            sys_wait(2000);
            $display("  [DDR3] Init done");
        end
    endtask

    // ---- 从 Slave FIFO 读一字 ----
    task slave_read_word;
        begin
            @(posedge i_rd_clk);
            while (o_slave_fifo_data_wr_en_n !== 1'b0)
                @(posedge i_rd_clk);
            slave_rd_result = o_slave_fifo_data;
        end
    endtask

    // ---- 从 Slave FIFO 读 N 字 ----
    task slave_read_words;
        input integer num;
        integer k;
        begin
            for (k = 0; k < num; k = k + 1)
                slave_read_word;
        end
    endtask

    // ---- 等待 STATUS.frame_num > 0 ----
    task wait_frame_available;
        input integer timeout_us;
        integer t;
        reg [31:0] sts;
        begin
            t = 0;
            axi_read(ADDR_STATUS, sts);
            while ((sts & STS_FRAME_NUM) == 0 && t < timeout_us) begin
                #1000;
                t = t + 1;
                axi_read(ADDR_STATUS, sts);
            end
            if (t >= timeout_us) begin
                $display("  [WAIT] Timeout: no frame available after %0d us", timeout_us);
                $stop;
            end else
                $display("  [WAIT] Frame available, frame_num=%0d, sts=0x%08h",
                         sts & STS_FRAME_NUM, sts);
        end
    endtask

    // ---- 等待 intr 拉高 ----
    task wait_intr;
        input integer timeout_cycles;
        integer t;
        begin
            t = 0;
            while (!intr && t < timeout_cycles) begin
                @(posedge s00_axi_aclk);
                t = t + 1;
            end
            if (t >= timeout_cycles)  begin
                $display("  [FAIL] intr timeout after %0d cycles", timeout_cycles);
                $stop;
            end
            else
                $display("  [PASS] intr asserted after %0d cycles", t);
        end
    endtask

    // ==================================================================
    // 主激励
    // ==================================================================
    initial begin : stimulus

        // ---- 初始化 ----
        s00_axi_aresetn  = 1'b0;
        mig_rst_n        = 1'b0;
        axi_awaddr       = 6'h0;
        axi_awvalid      = 1'b0;
        axi_wdata        = 32'h0;
        axi_wstrb        = 4'h0;
        axi_wvalid       = 1'b0;
        axi_bready       = 1'b0;
        axi_araddr       = 6'h0;
        axi_arvalid      = 1'b0;
        axi_rready       = 1'b0;
        axi_awprot       = 3'h0;
        axi_arprot       = 3'h0;
        i_adc_data       = 8'h0;
        adc_cnt          = 4'h0;
        test_num         = 4'd0;
        i_slave_fifo_empty_n = 1'b1;
        i_slave_fifo_full_n  = 1'b1;

        $display("============================================================");
        $display("  test_ccd_controller_axi");
        $display("============================================================");

        // ---- 释放 mig 复位 ----
        sys_wait(50);
        mig_rst_n = 1'b1;

        // ---- 释放 ip 复位 ----
        sys_wait(50);
        s00_axi_aresetn = 1'b1;

        // ---- 等待 DDR3 校准 ----
        wait_ddr3_init;


        // ================================================================
        // 测试 1: 寄存器读写验证
        // ================================================================
        $display("========================================");
        $display("[TEST 1] Register R/W");
        $display("========================================");
        test_num = 4'd1;

        // 写 CTRL: exposure=1, freq_sel=1, mock_mode=0, read_mode=1, cdsclk_delay=10
        axi_write(ADDR_CTRL, {20'h0, 7'd10, 2'b01, 1'b0, 1'b1, 1'b1});
        axi_read_dbg(ADDR_CTRL, "CTRL");

        // 写 IMG_SIZE: width=8, height=2
        axi_write(ADDR_IMG_SIZE, {16'd2, 16'd8});
        axi_read_dbg(ADDR_IMG_SIZE, "IMG_SIZE");

        // 写 BEVEL_BLANK: left=1,top=1,right=1,bottom=1,blank_l=1,blank_r=1
        axi_write(ADDR_BEVEL_BLANK, {8'h0, 4'd1, 4'd1, 4'd1, 4'd1, 4'd1, 4'd1});
        axi_read_dbg(ADDR_BEVEL_BLANK, "BEVEL_BLANK");

        // 读 STATUS (应能看到 ddr3_init_done=1)
        axi_read_dbg(ADDR_STATUS, "STATUS");
        if (axi_rdata & STS_DDR3_DONE)
            $display("[PASS] ddr3_init_done=1 in STATUS");
        else begin
            $display("[FAIL] ddr3_init_done not set, got 0x%08h", axi_rdata);
            $stop;
        end

        // $stop;

        // ================================================================
        // 测试 2: line binning 采集 + TRIGGER 触发帧发送
        // ================================================================
        $display("========================================");
        $display("[TEST 2] Line binning + TRIGGER → Slave FIFO");
        $display("========================================");
        test_num = 4'd2;

        // 配置 CTRL: exposure=1, freq_sel=0=100kHz, read_mode=0=line binning
        axi_write(ADDR_CTRL, {20'h0, 7'd0, 2'd0, 1'b0, 1'b0, 1'b1});

        // 拉低 exposure 启动采集
        axi_write(ADDR_CTRL, {20'h0, 7'd0, 2'd0, 1'b0, 1'b0, 1'b0});
        wait_us(300);

        // 拉高 exposure 结束采集
        axi_write(ADDR_CTRL, {20'h0, 7'd0, 2'd0, 1'b0, 1'b0, 1'b1});

        // 等待 DDR 写入 + CDC 稳定
        rd_wait(50);
        sys_wait(50);

        // 等待帧缓存中有数据
        wait_frame_available(500);

        // 触发帧发送 (写 TRIGGER[0]=1)
        $display("  Triggering TX via TRIGGER register...");
        axi_write(ADDR_TRIGGER, 32'h00000001);

        // 读 TRIGGER (应返回 0 — 自清)
        axi_read_dbg(ADDR_TRIGGER, "TRIGGER (expect 0)");

        // 从 Slave FIFO 读出
        slave_read_words(8);
        $display("  Slave FIFO read complete, last=0x%04h", slave_rd_result);

        // $stop;
        
        // ================================================================
        // 测试 3: 中断 — tx_done IRQ
        // ================================================================
        $display("========================================");
        $display("[TEST 3] Interrupt — tx_done IRQ");
        $display("========================================");
        test_num = 4'd3;

        // 清中断状态, 使能 tx_done 中断
        axi_write(ADDR_INTR_STS, INTR_TX_DONE);         // 确保 pending 清零
        axi_write(ADDR_INTR_EN, INTR_TX_DONE);
        axi_read_dbg(ADDR_INTR_EN, "INTR_EN");

        if (intr)
            $display("  Warning: intr already high before trigger");

        // 再做一帧采集
        axi_write(ADDR_CTRL, {20'h0, 7'd0, 2'd0, 1'b0, 1'b0, 1'b0});  // exposure=0
        wait_us(300);
        axi_write(ADDR_CTRL, {20'h0, 7'd0, 2'd0, 1'b0, 1'b0, 1'b1});  // exposure=1
        rd_wait(50);
        sys_wait(50);
        wait_frame_available(500);

        // 触发发送
        axi_write(ADDR_TRIGGER, 32'h00000001);
        slave_read_words(8);

        // 等待 intr 拉高
        wait_intr(500);

        // 读 INTR_STS
        axi_read_dbg(ADDR_INTR_STS, "INTR_STS");
        if (axi_rdata & INTR_TX_DONE)
            $display("[PASS] tx_done_pending=1 in INTR_STS");
        else begin
            $display("[FAIL] tx_done_pending not set, got 0x%08h", axi_rdata);
            $stop;
        end

        // 写 1 清除中断
        $display("  Clearing INTR_STS...");
        axi_write(ADDR_INTR_STS, INTR_TX_DONE);
        sys_wait(5);

        // 验证清除
        axi_read_dbg(ADDR_INTR_STS, "INTR_STS (after clear)");
        if (!intr)
            $display("[PASS] intr deasserted after clear");
        else begin
            $display("[FAIL] intr still high");
            $stop;
        end

        // $stop;
        
        // ================================================================
        // 测试 4: STATUS 实时读取
        // ================================================================
        $display("========================================");
        $display("[TEST 4] STATUS live read");
        $display("========================================");
        test_num = 4'd4;

        axi_read_dbg(ADDR_STATUS, "STATUS(final)");

        // ================================================================
        // 测试 5: 异常中断 — INTR_STS[8] 读回位 + W1C 清除
        // ================================================================
        $display("========================================");
        $display("[TEST 5] Exception IRQ — INTR_STS readback bit + W1C");
        $display("========================================");
        test_num = 4'd5;

        // 清中断, 使能 exception 中断
        axi_write(ADDR_INTR_STS, INTR_EXCEPTION);
        axi_write(ADDR_INTR_EN,  INTR_EXCEPTION);
        axi_read_dbg(ADDR_INTR_EN, "INTR_EN");

        // line binning 8x2, 各消隐=1
        axi_write(ADDR_IMG_SIZE, {16'd2, 16'd8});
        axi_write(ADDR_BEVEL_BLANK, {8'h0, 4'd1, 4'd1, 4'd1, 4'd1, 4'd1, 4'd1});
        axi_write(ADDR_CTRL, {20'h0, 7'd0, 2'd0, 1'b0, 1'b0, 1'b1});  // exposure=1: 曝光中
        axi_write(ADDR_CTRL, {20'h0, 7'd0, 2'd0, 1'b0, 1'b0, 1'b0});  // 下降沿→触发读出

        // 帧开始已锁存 depth=8; 读出中把宽度改为 16 → pixel_cnt(16)!=depth(8) → 帧异常
        wait_us(80);
        axi_write(ADDR_IMG_SIZE, {16'd2, 16'd16});

        // 轮询 intr (~300us 后帧结束; 超时 800us)
        wait_timeout = 0;
        while (!intr && wait_timeout < 80) begin
            #10000;
            wait_timeout = wait_timeout + 1;
        end
        if (wait_timeout >= 80) begin
            $display("  [FAIL] exception intr timeout");
            $stop;
        end
        $display("  [PASS] exception intr asserted after ~%0d us", wait_timeout * 10);

        // 读 INTR_STS: exception 必须在 bit[8], bit[7] 必须为 0 (回归断言)
        axi_read_dbg(ADDR_INTR_STS, "INTR_STS");
        if (axi_rdata & INTR_EXCEPTION)
            $display("  [PASS] exception_pending=1 at bit[8]");
        else begin
            $display("  [FAIL] exception_pending not at bit[8], got 0x%08h", axi_rdata);
            $stop;
        end
        if (axi_rdata & 32'h00000080)
            $display("  [FAIL] exception leaked to bit[7], got 0x%08h", axi_rdata);
        else
            $display("  [PASS] bit[7] stays 0");

        // STATUS: exception_cnt 应为 1
        axi_read_dbg(ADDR_STATUS, "STATUS(after exception)");
        if ((axi_rdata & STS_EXCEP_CNT) != 0)
            $display("  [PASS] exception_cnt > 0 in STATUS");
        else begin
            $display("  [FAIL] exception_cnt == 0 in STATUS");
            $stop;
        end

        // W1C: 写 0x100 清除, intr 拉低
        axi_write(ADDR_INTR_STS, INTR_EXCEPTION);
        sys_wait(5);
        axi_read_dbg(ADDR_INTR_STS, "INTR_STS (after clear)");
        if (!intr && !(axi_rdata & INTR_EXCEPTION))
            $display("  [PASS] exception cleared, intr deasserted");
        else begin
            $display("  [FAIL] clear failed, intr=%0d sts=0x%08h", intr, axi_rdata);
            $stop;
        end

        $display("============================================================");
        $display("  ALL TESTS COMPLETE");
        $display("============================================================");

        $finish;
    end

endmodule

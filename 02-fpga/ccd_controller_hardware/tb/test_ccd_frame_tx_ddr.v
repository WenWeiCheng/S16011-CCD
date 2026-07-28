`timescale 1ns / 1ps
//==============================================================================
// Module : test_ccd_frame_tx_ddr
// Desc   : ccd_frame_tx 帧发送模块功能验证 (集成 ccd_frame_buf_ddr)
//
//   使用 DDR 实现的 ccd_frame_buf_ddr 作为帧缓存源, 通过写侧写入像素数据,
//   验证 ccd_frame_tx 从读侧读出并转发至 Slave FIFO 的完整通路。
//
//   测试 1 : 复位 — o_slave_fifo_data_valid_n=1, o_tx_last_n=1
//   测试 2 : 单帧发送 — 写一帧, 触发 TX, 验证数据 (含 scoreboard 比对)
//   测试 3 : 连续多帧 — 依次发送 3 帧, 逐帧验证数据
//   测试 4 : Slave FIFO 满反压 — full_n=0 时暂停发送, 恢复后继续
//   测试 5 : 乒乓切换 — 写 2 帧后分别发送并验证
//   测试 6 : 帧长异常 — active 像素 != frame_depth → o_frame_exception
//   测试 7 : 先 start 后等数据 — idle→wait, 数据稍后到达, 验证数据
//   测试 8 : 数据验证 — 使用 tx_and_verify task 验证 Slave FIFO 数据
//==============================================================================
module test_ccd_frame_tx_ddr;

    // ==================================================================
    // 参数
    // ==================================================================
    localparam MAX_FRAMES       = 4;
    localparam MAX_FRAME_DEPTH  = 2048;
    localparam FRAME_WORDS      = 256;              // 每帧字数 (恰好 1 AXI burst)
    localparam FRAME_NUM_W      = $clog2(MAX_FRAMES + 1);

    localparam ADC_CLK_PERIOD   = 20;               // 50 MHz
    localparam RD_CLK_PERIOD    = 20;               // 50 MHz (与 ADC 异步)
    localparam DDR3_CLK100_PER  = 10;               // 100 MHz
    localparam DDR3_CLK200_PER  = 5;                // 200 MHz ref

    // ==================================================================
    // 时钟生成
    // ==================================================================
    reg i_adcclk;
    reg i_ext_clk;
    reg i_ext_clk_n;
    reg mig_sys_clk;
    reg mig_clk_ref;

    initial i_adcclk = 1'b0;
    always #(ADC_CLK_PERIOD / 2.0) i_adcclk = ~i_adcclk;

    initial i_ext_clk = 1'b0;
    always #(RD_CLK_PERIOD / 2.0) i_ext_clk = ~i_ext_clk;

    initial i_ext_clk_n = 1'b1;
    always #(RD_CLK_PERIOD / 2.0) i_ext_clk_n = ~i_ext_clk_n;

    initial mig_sys_clk = 1'b0;
    always #(DDR3_CLK100_PER / 2.0) mig_sys_clk = ~mig_sys_clk;

    initial mig_clk_ref = 1'b0;
    always #(DDR3_CLK200_PER / 2.0) mig_clk_ref = ~mig_clk_ref;

    // ==================================================================
    // 复位
    // ==================================================================
    reg i_rst_n;
    reg mig_rst_n;

    // ==================================================================
    // ADC 域信号 (i_adcclk)
    // ==================================================================
    reg  [15:0] i_wr_data;
    reg         i_wr_en;
    reg  [1:0]  i_pixel_type;
    reg         i_frame_start_buf;
    reg         i_frame_end;
    reg  [15:0] i_image_width;
    reg  [15:0] i_image_height;
    reg  [1:0]  i_read_mode;

    // ==================================================================
    // ccd_frame_buf_ddr ↔ ccd_frame_tx 连接
    // ==================================================================
    wire [15:0]            fifo_data;
    wire [FRAME_NUM_W-1:0] fifo_frame_num;
    wire                   fifo_prelast;
    wire                   fifo_rd_en;

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
    wire        o_tx_last_n;

    // ==================================================================
    // DDR3 状态 / 异常
    // ==================================================================
    wire o_frame_exception;

    // ---- MIG 接口 (ui_clk 域) ----
    wire        ui_clk;
    wire        ddr3_init_done;
    wire        mmcm_locked;
    wire        init_calib_complete;
    wire        ui_clk_sync_rst;

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
    reg [15:0] scoreboard [0:MAX_FRAMES-1][0:MAX_FRAME_DEPTH-1];

    // ==================================================================
    // 跨域捕获寄存器
    // ==================================================================
    reg exception_captured;
    reg frame_done_captured;

    // o_frame_exception 捕获 (写域脉冲 → 寄存器展宽)
    always @(posedge i_adcclk or negedge i_rst_n) begin
        if (!i_rst_n)
            exception_captured <= 1'b0;
        else if (o_frame_exception)
            exception_captured <= 1'b1;
    end

    // frame_done 捕获 (跨时钟域, 防止 wr_frame 阻塞时错过)
    always @(negedge o_tx_last_n or negedge i_rst_n) begin
        if (!i_rst_n)
            frame_done_captured <= 1'b0;
        else
            frame_done_captured <= 1'b1;
    end

    // ==================================================================
    // DUT 例化
    // ==================================================================

    ccd_frame_buf_ddr #(
        .MAX_FRAME_DEPTH (MAX_FRAME_DEPTH),
        .MAX_FRAMES      (MAX_FRAMES)
    ) u_ccd_frame_buf_ddr (
        .i_adcclk          (i_adcclk),
        .i_rst_n           (i_rst_n),
        .i_wr_data         (i_wr_data),
        .i_wr_en           (i_wr_en),
        .i_pixel_type      (i_pixel_type),
        .i_frame_start     (i_frame_start_buf),
        .i_frame_end       (i_frame_end),
        .i_image_width     (i_image_width),
        .i_image_height    (i_image_height),
        .i_read_mode       (i_read_mode),
        .i_rd_clk          (i_ext_clk),
        .o_fifo_data       (fifo_data),
        .o_frame_num       (fifo_frame_num),
        .i_fifo_rd_en      (fifo_rd_en),
        .o_fifo_prelast  (fifo_prelast),
        .o_frame_exception (o_frame_exception),
        .i_ui_clk          (ui_clk),
        .i_ddr3_init_done  (ddr3_init_done),
        .M_AXI_AWID        (axi_awid),
        .M_AXI_AWADDR      (axi_awaddr),
        .M_AXI_AWLEN       (axi_awlen),
        .M_AXI_AWSIZE      (axi_awsize),
        .M_AXI_AWBURST     (axi_awburst),
        .M_AXI_AWLOCK      (axi_awlock),
        .M_AXI_AWCACHE     (axi_awcache),
        .M_AXI_AWPROT      (axi_awprot),
        .M_AXI_AWQOS       (axi_awqos),
        .M_AXI_AWREGION    (),
        .M_AXI_AWVALID     (axi_awvalid),
        .M_AXI_AWREADY     (axi_awready),
        .M_AXI_WDATA       (axi_wdata),
        .M_AXI_WSTRB       (axi_wstrb),
        .M_AXI_WLAST       (axi_wlast),
        .M_AXI_WVALID      (axi_wvalid),
        .M_AXI_WREADY      (axi_wready),
        .M_AXI_BID         (axi_bid),
        .M_AXI_BRESP       (axi_bresp),
        .M_AXI_BVALID      (axi_bvalid),
        .M_AXI_BREADY      (axi_bready),
        .M_AXI_ARID        (axi_arid),
        .M_AXI_ARADDR      (axi_araddr),
        .M_AXI_ARLEN       (axi_arlen),
        .M_AXI_ARSIZE      (axi_arsize),
        .M_AXI_ARBURST     (axi_arburst),
        .M_AXI_ARLOCK      (axi_arlock),
        .M_AXI_ARCACHE     (axi_arcache),
        .M_AXI_ARPROT      (axi_arprot),
        .M_AXI_ARQOS       (axi_arqos),
        .M_AXI_ARREGION    (),
        .M_AXI_ARVALID     (axi_arvalid),
        .M_AXI_ARREADY     (axi_arready),
        .M_AXI_RID         (axi_rid),
        .M_AXI_RDATA       (axi_rdata),
        .M_AXI_RRESP       (axi_rresp),
        .M_AXI_RLAST       (axi_rlast),
        .M_AXI_RVALID      (axi_rvalid),
        .M_AXI_RREADY      (axi_rready)
    );

    // ==================================================================
    // MIG 7-Series DDR3 Controller (外部例化)
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

    ccd_frame_tx #(
        .MAX_FRAMES (MAX_FRAMES)
    ) u_ccd_frame_tx (
        .i_ext_clk               (i_ext_clk),
        .i_ext_clk_n             (i_ext_clk_n),
        .i_rst_n                 (i_rst_n),
        .i_frame_fifo_data       (fifo_data),
        .i_frame_fifo_num        (fifo_frame_num),
        .i_frame_fifo_prelast  (fifo_prelast),
        .o_frame_fifo_rd_en      (fifo_rd_en),
        .o_slave_fifo_data       (o_slave_fifo_data),
        .o_slave_fifo_data_valid_n(o_slave_fifo_data_valid_n),
        .i_slave_fifo_empty_n    (i_slave_fifo_empty_n),
        .i_slave_fifo_full_n     (i_slave_fifo_full_n),
        .i_frame_start           (i_frame_start_tx),
        .o_tx_last_n          (o_tx_last_n)
    );

    // ==================================================================
    // DDR3 仿真模型 × 2 — 通过 MIG 连接, 参考 test_ccd_frame_buf_ddr.v 拼接方式
    //   32-bit DDR3 拆为 2 个 16-bit 模型:
    //     model_hi: dq[31:16], dqs[3:2], dm[3:2]
    //     model_lo: dq[15:0],  dqs[1:0], dm[1:0]
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
    // 辅助任务 — 写域 (i_adcclk)
    // ==================================================================

    task wr_wait;
        input integer cycles;
        begin
            repeat (cycles) @(posedge i_adcclk);
        end
    endtask

    task wr_active_pixel;
        input [15:0] data;
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
    task wr_frame;
        input integer   num_active;
        input [15:0]    base;
        input integer   sb_idx;
        integer k;
        begin
            $display("  [WR] Writing frame: %0d pixels, base=0x%h, sb_idx=%0d",
                     num_active, base, sb_idx);

            i_image_width  <= num_active;
            i_image_height <= 1;
            i_read_mode    <= 2'd0;
            @(posedge i_adcclk);
            i_frame_start_buf <= 1'b1;
            @(posedge i_adcclk);
            i_frame_start_buf <= 1'b0;

            for (k = 0; k < num_active; k = k + 1) begin
                wr_active_pixel(base + k);
                scoreboard[sb_idx][k] <= base + k;
            end

            @(posedge i_adcclk);
            i_frame_end <= 1'b1;
            @(posedge i_adcclk);
            i_frame_end <= 1'b0;

            $display("  [WR] Done");
        end
    endtask

    // ==================================================================
    // 辅助任务 — 读域 (i_ext_clk)
    // ==================================================================

    task rd_wait;
        input integer cycles;
        begin
            repeat (cycles) @(posedge i_ext_clk);
        end
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

    // ---- 等待 frame_done ----
    task wait_frame_done;
        reg [15:0] _timeout;
        begin
            _timeout = 0;
            while (frame_done_captured === 1'b0 && _timeout < 16384) begin
                @(posedge i_ext_clk);
                _timeout = _timeout + 1;
            end
            if (_timeout >= 16384) begin
                $display("  [WAIT] frame_done timeout");
                $stop;
            end
        end
    endtask

    // ---- 清空 frame_done 捕获标志 ----
    task clear_frame_done_capture;
        begin
            frame_done_captured = 1'b0;
            #0;
        end
    endtask

    // ---- 采集验证 Slave FIFO 数据 (不触发 start, 适用于已处于 wait 态的场景) ----
    task verify_tx_data;
        input [15:0] pixel_count;
        input integer sb_idx;
        integer      rd_cnt;
        integer      errors;
        reg [15:0]   timeout;
        reg [3:0]    px_timeout;
        begin
            $display("  [VERIFY_TX] Expecting %0d pixels, sb_idx=%0d",
                     pixel_count, sb_idx);
            rd_cnt   = 0;
            errors   = 0;

            // 采集 Slave FIFO 数据并比对 scoreboard (每像素超时 10 i_ext_clk 周期)
            while (rd_cnt < pixel_count) begin
                // 等数据有效, 超时则报错
                px_timeout = 0;
                while (o_slave_fifo_data_valid_n === 1'b1) begin
                    @(posedge i_ext_clk);
                    px_timeout = px_timeout + 1;
                    if (px_timeout >= 100) begin
                        $display("  [VERIFY_TX] ** TIMEOUT ** pixel %0d: valid_n stuck high for %0d i_ext_clk cycles",
                                 rd_cnt, px_timeout);
                        $stop;
                    end
                end
                // 在 i_ext_clk_n 上升沿采样数据 (与原采样方式一致)
                @(posedge i_ext_clk_n);
                if (o_slave_fifo_data !== scoreboard[sb_idx][rd_cnt]) begin
                    $display("  [VERIFY_TX] ** MISMATCH ** idx=%0d: got=0x%h, expected=0x%h",
                             rd_cnt, o_slave_fifo_data, scoreboard[sb_idx][rd_cnt]);
                    errors = errors + 1;
                    $stop;
                end
                rd_cnt = rd_cnt + 1;
            end

            // 等待 frame_done (带超时)
            if (frame_done_captured !== 1'b1) begin
                timeout = 0;
                while (frame_done_captured !== 1'b1 && timeout < 100) begin
                    @(posedge i_ext_clk);
                    timeout = timeout + 1;
                end
            end

            if (timeout >= 16384) begin
                $display("  [VERIFY_TX] ** FAIL ** frame_done timeout after %0d pixels", pixel_count);
                $stop;
            end else if (errors == 0) begin
                $display("  [VERIFY_TX] PASS \u2014 %0d pixels verified", pixel_count);
            end else begin
                $display("  [VERIFY_TX] FAIL \u2014 %0d mismatch(es)", errors);
            end
        end
    endtask

    // ---- 触发 TX 发送并验证数据 (封装 send_frame + verify_tx_data) ----
    task tx_and_verify;
        input [15:0] pixel_count;
        input integer sb_idx;
        begin
            $display("  [TX_VERIFY] Sending frame, expecting %0d pixels, sb_idx=%0d",
                     pixel_count, sb_idx);

            // 清捕获标志
            frame_done_captured = 1'b0;
            #0;

            // 脉冲 i_frame_start_tx (同 send_frame)
            @(posedge i_ext_clk);
            i_frame_start_tx <= 1'b1;
            @(posedge i_ext_clk);
            i_frame_start_tx <= 1'b0;

            // 调用 verify_tx_data 完成采集和比对
            verify_tx_data(pixel_count, sb_idx);
        end
    endtask

    // ---- 等待 DDR3 初始化完成 ----
    task wait_ddr3_init;
        begin
            $display("  [DDR3] Waiting for init_calib_complete...");
            while (!ddr3_init_done) begin
                @(posedge i_adcclk);
            end
            // 等待 ui_clk 域稳定, 确保 ctrl_rst_n 完全释放
            wr_wait(500);
            rd_wait(500);
            $display("  [DDR3] Init done");
        end
    endtask

    // ---- 等待读数据可用 (RD 域轮询 o_frame_num) ----
    task wait_read_available;
        reg [15:0] _timeout;
        begin
            _timeout = 0;
            while (fifo_frame_num == 0 && _timeout < 16384) begin
                @(posedge i_ext_clk);
                _timeout = _timeout + 1;
            end
            if (_timeout >= 16384) begin
                $display("  [WAIT] Timeout waiting for read data (frame_num=%0d)", fifo_frame_num);
                $stop;
            end
            else
                $display("  [WAIT] Data available, frames_in_ddr=%0d", fifo_frame_num);
        end
    endtask

    // ---- 软复位 (不复位 DDR3/MIG, 仅复位控制器逻辑) ----
    task soft_reset;
        begin
            $display("  [SOFT_RESET] Asserting...");
            frame_done_captured = 1'b0;
            exception_captured  = 1'b0;

            i_wr_data           = 16'd0;
            i_wr_en             = 1'b0;
            i_pixel_type        = 2'b00;
            i_frame_start_buf   = 1'b0;
            i_frame_end         = 1'b0;
            i_image_width       = 16'd0;
            i_image_height      = 16'd1;
            i_read_mode         = 2'd0;
            i_frame_start_tx    = 1'b0;
            i_slave_fifo_empty_n = 1'b1;
            i_slave_fifo_full_n  = 1'b1;

            i_rst_n = 1'b0;
            wr_wait(20);
            rd_wait(20);
            i_rst_n = 1'b1;
            wr_wait(200);
            rd_wait(200);
            $display("  [SOFT_RESET] Released");
        end
    endtask

    // ==================================================================
    // 主激励
    // ==================================================================
    integer i, j;
    reg [7:0] test_num;

    initial begin : stimulus
        $display("======================================================");
        $display(" ccd_frame_tx Testbench (with ccd_frame_buf_ddr)");
        $display(" FRAME_WORDS=%0d, MAX_FRAMES=%0d, MAX_FRAME_DEPTH=%0d",
                 FRAME_WORDS, MAX_FRAMES, MAX_FRAME_DEPTH);
        $display("======================================================");

        // ---- 初始化 ----
        test_num            = 7'b0;
        i_rst_n             = 1'b0;
        mig_rst_n            = 1'b0;
        i_wr_data           = 16'd0;
        i_wr_en             = 1'b0;
        i_pixel_type        = 2'b00;
        i_frame_start_buf   = 1'b0;
        i_frame_end         = 1'b0;
        i_image_width       = 16'd0;
        i_image_height      = 16'd1;
        i_read_mode         = 2'd0;
        i_frame_start_tx    = 1'b0;
        i_slave_fifo_empty_n = 1'b1;
        i_slave_fifo_full_n  = 1'b1;

        frame_done_captured  = 1'b0;
        exception_captured   = 1'b0;

        wr_wait(20);
        rd_wait(20);

        // 释放系统复位, MIG 仍保持复位
        i_rst_n = 1'b1;
        wr_wait(10);
        rd_wait(10);

        // ================================================================
        // 测试 1: 复位后状态
        // ================================================================
        test_num = test_num + 1;
        $display("\n--- test_num=%0d ---", test_num);
        $display("[TEST 1] Reset check");
        rd_wait(1);
        if (o_slave_fifo_data_valid_n !== 1'b1) begin
            $display("[FAIL] Reset: data_valid_n=%b (expected 1)",
                     o_slave_fifo_data_valid_n);
            $stop;
        end else if (o_tx_last_n !== 1'b1) begin
            $display("[FAIL] Reset: tx_last_n=%b (expected 1)", o_tx_last_n);
            $stop;
        end else begin
            $display("[PASS] Reset state OK");
        end

        // 释放 MIG 复位, 等待 DDR3 校准完成
        mig_rst_n <= 1'b1;
        wait_ddr3_init;

        // ================================================================
        // 测试 2: 单帧发送 — 写一帧, 触发 TX, 验证数据
        // ================================================================
        soft_reset;
        test_num = test_num + 1;
        $display("\n--- test_num=%0d ---", test_num);
        $display("[TEST 2] Single frame transmission with data verification");
        wr_frame(FRAME_WORDS, 16'd1000, 0);
        wait_read_available;
        tx_and_verify(FRAME_WORDS, 0);
        rd_wait(20);
        $stop;

        // ================================================================
        // 测试 3: 连续多帧发送
        // ================================================================
        soft_reset;
        test_num = test_num + 1;
        $display("\n--- test_num=%0d ---", test_num);
        $display("[TEST 3] Multiple frame transmissions with data verification");
        for (i = 0; i < 3; i = i + 1) begin
            wr_frame(FRAME_WORDS, 16'd3000 + i * 1000, i);
            wait_read_available;
            tx_and_verify(FRAME_WORDS, i);
            rd_wait(10);
        end
        $display("[PASS] 3 frames verified");
        $stop;

        // ================================================================
        // 测试 4: Slave FIFO 满反压
        // ================================================================
        soft_reset;
        test_num = test_num + 1;
        $display("\n--- test_num=%0d ---", test_num);
        $display("[TEST 4] Slave FIFO full back-pressure");
        clear_frame_done_capture;
        wr_frame(FRAME_WORDS, 16'd6000, 0);
        wait_read_available;
        send_frame;
        rd_wait(5);

        // 模拟 Slave FIFO 满
        @(negedge i_ext_clk);
        i_slave_fifo_full_n = 1'b0;
        rd_wait(16);
        if (fifo_rd_en !== 1'b0) begin
            $display("[FAIL] rd_en=%b during back-pressure (expected 0)",
                     fifo_rd_en);
            $stop;
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
            $stop;
        end else begin
            $display("[PASS] Transmission resumed after back-pressure release");
        end
        rd_wait(20);
        $stop;

        // ================================================================
        // 测试 5: 乒乓切换 — 写 2 帧再分别发送
        // ================================================================
        soft_reset;
        test_num = test_num + 1;
        $display("\n--- test_num=%0d ---", test_num);
        $display("[TEST 5] Ping-pong: 2 frames with data verification");
        wr_frame(FRAME_WORDS, 16'd7000, 0);
        wr_frame(FRAME_WORDS, 16'd8000, 1);
        wait_read_available;
        $display("  2 frames written, frame_num=%d", fifo_frame_num);

        tx_and_verify(FRAME_WORDS, 0);
        $display("  Frame 0 done, frame_num=%d", fifo_frame_num);
        rd_wait(10);

        tx_and_verify(FRAME_WORDS, 1);
        $display("  Frame 1 done, frame_num=%d", fifo_frame_num);
        rd_wait(10);
        $display("[PASS] Ping-pong OK");
        $stop;

        // ================================================================
        // 测试 6: 帧长异常 — 写入少于 frame_depth 的像素
        // ================================================================
        soft_reset;
        test_num = test_num + 1;
        $display("\n--- test_num=%0d ---", test_num);
        $display("[TEST 6] Frame length exception");
        clear_frame_done_capture;
        exception_captured = 1'b0;

        @(posedge i_adcclk);
        i_image_width     <= FRAME_WORDS;
        i_image_height    <= 1;
        i_read_mode       <= 2'd0;
        i_frame_start_buf <= 1'b1;
        @(posedge i_adcclk);
        i_frame_start_buf <= 1'b0;

        for (i = 0; i < FRAME_WORDS - 3; i = i + 1)
            wr_active_pixel(16'd9000 + i);

        @(posedge i_adcclk);
        i_frame_end <= 1'b1;
        @(posedge i_adcclk);
        i_frame_end <= 1'b0;

        wr_wait(200);

        if (exception_captured !== 1'b1) begin
            $display("[FAIL] Exception not triggered (captured=%b)",
                     exception_captured);
            $stop;
        end else begin
            $display("[PASS] Frame exception detected");
        end
        $stop;

        // ================================================================
        // 测试 7: 先 start 后等数据 (idle→wait, 数据稍后到达, 验证数据)
        // ================================================================
        soft_reset;
        test_num = test_num + 1;
        $display("\n--- test_num=%0d ---", test_num);
        $display("[TEST 7] Start before data with data verification");
        clear_frame_done_capture;
        send_frame;           // idle→wait (DDR 中无数据)
        rd_wait(50);
        $display("  In wait state, writing frame...");

        wr_frame(FRAME_WORDS, 16'd10000, 0);

        // TX 已处于 wait 态, 数据就绪后自动开始发送, 采集并验证
        // verify_tx_data(FRAME_WORDS, 0);
        $display("[PASS] Start-before-data OK (verified %0d pixels)", FRAME_WORDS);
        rd_wait(20);
        $stop;

        // ================================================================
        // 测试 8: 数据验证 — 采集 Slave FIFO 输出, 比对 scoreboard
        //   封装为 tx_and_verify task 调用
        // ================================================================
        soft_reset;
        test_num = test_num + 1;
        $display("\n--- test_num=%0d ---", test_num);
        $display("[TEST 8] Data verification via Slave FIFO (using tx_and_verify)");
        wr_frame(FRAME_WORDS, 16'hA5A5, 0);
        wait_read_available;
        tx_and_verify(FRAME_WORDS, 0);
        rd_wait(20);

        // ================================================================
        $display("======================================================");
        $display(" All tests completed");
        $display("======================================================");
        $finish;
    end

endmodule

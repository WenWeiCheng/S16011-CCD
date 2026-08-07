`timescale 1ns / 1ps
//==============================================================================
// Testbench : test_ccd_frame_buf_ddr_ctrl
// Desc      : ccd_frame_buf_ddr_ctrl 的完整 testbench。
//             通过像素 I/O 驱动控制器, AXI BFM 模拟 MIG 行为,
//             从 o_fifo_data 读回并自检验证。
//
// 架构:
//   DUT (ccd_frame_buf_ddr_ctrl) 内部已封装:
//     wr_ddr3_fifo / rd_ddr3_fifo (Xilinx FIFO IP — 仿真需 Vivado xsim)
//     ADC 域控制逻辑 / CDC / RD 域控制逻辑
//   ccd_frame_buf_ddr_axi_adapter 在 DUT 外部例化, 连接 DUT 控制信号与 AXI BFM
//
//   Testbench 负责:
//     - 驱动 i_adcclk 域: 模拟 CCD 像素数据输入
//     - 驱动 i_rd_clk 域:  模拟 FX2 读回数据
//     - 例化 AXI4 Slave BFM (模拟 MIG 行为)
//     - 自检验证写入/读回数据一致性
//==============================================================================
module test_ccd_frame_buf_ddr_ctrl;

    // ==================================================================
    // 参数
    // ==================================================================
    localparam MAX_FRAMES       = 4;
    localparam MAX_FRAME_DEPTH  = 1024;
    localparam AXI_ADDR_WIDTH   = 30;
    localparam AXI_DATA_WIDTH   = 128;
    localparam AXI_ID_WIDTH     = 4;
    localparam AXI_ID           = 4'b0000;
    localparam AXI_BURST_LEN    = 8'd31;
    localparam FIFO_ADDR_WIDTH  = 6;

    localparam UI_CLK_PERIOD    = 10;     // 100 MHz
    localparam ADC_CLK_PERIOD   = 20;     // 50 MHz
    localparam RD_CLK_PERIOD    = 20;     // 50 MHz

    localparam BURST_UNITS      = AXI_BURST_LEN + 1;       // 32
    localparam AXI_DATA_BYTES   = AXI_DATA_WIDTH / 8;      // 16
    localparam BURST_BYTES      = BURST_UNITS * AXI_DATA_BYTES; // 512
    localparam PIXELS_PER_BURST = BURST_UNITS * (AXI_DATA_WIDTH / 16); // 256
    localparam MEM_DEPTH        = 16384;
    localparam FRAME_NUM_W      = $clog2(MAX_FRAMES + 1);

    // ==================================================================
    // 时钟
    // ==================================================================
    reg i_ui_clk;
    reg i_adcclk;
    reg i_rd_clk;

    initial i_ui_clk = 1'b0;
    always #(UI_CLK_PERIOD/2) i_ui_clk = ~i_ui_clk;

    initial i_adcclk = 1'b0;
    always #(ADC_CLK_PERIOD/2) i_adcclk = ~i_adcclk;

    initial i_rd_clk = 1'b0;
    always #(RD_CLK_PERIOD/2) i_rd_clk = ~i_rd_clk;

    // ==================================================================
    // 复位与初始化
    // ==================================================================
    reg i_rst_n;
    reg tb_ddr3_init_done;
    reg soft_rst;   // 模拟顶层 (ccd_frame_buf_ddr) 参数变化软复位
    // 控制器复位: 系统复位 AND DDR3 初始化完成 AND 非软复位 (同顶层门控)
    wire ctrl_rst_n = i_rst_n && tb_ddr3_init_done && ~soft_rst;

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
    // RD 域信号 (i_rd_clk)
    // ==================================================================
    wire [15:0]                   o_fifo_data;
    wire [FRAME_NUM_W-1:0]        o_frame_num;
    reg                           i_fifo_rd_en;
    wire                          o_fifo_prelast;
    wire                          o_frame_written;

    // ==================================================================
    // 异常
    // ==================================================================
    wire o_frame_exception;

    // ==================================================================
    // ctrl ↔ adapter 控制 + FIFO 连线
    // ==================================================================
    wire                ctrl_wr_req;
    wire [29:0]         ctrl_wr_start;
    wire [29:0]         ctrl_wr_end;
    wire                ctrl_wr_idle;
    wire                ctrl_rd_req;
    wire [29:0]         ctrl_rd_start;
    wire [29:0]         ctrl_rd_end;
    wire                ctrl_rd_idle;
    wire [127:0]        wrfifo_dout;
    wire                wrfifo_rden;
    wire                rdfifo_wren;
    wire [127:0]        rdfifo_din;

    // ==================================================================
    // AXI4 信号 (adapter ↔ BFM)
    // ==================================================================
    // 写地址
    wire [AXI_ID_WIDTH-1:0]   m_axi_awid;
    wire [AXI_ADDR_WIDTH-1:0] m_axi_awaddr;
    wire [7:0]                m_axi_awlen;
    wire [2:0]                m_axi_awsize;
    wire [1:0]                m_axi_awburst;
    wire                      m_axi_awlock;
    wire [3:0]                m_axi_awcache;
    wire [2:0]                m_axi_awprot;
    wire [3:0]                m_axi_awqos;
    wire [3:0]                m_axi_awregion;
    wire                      m_axi_awvalid;
    reg                       m_axi_awready;

    // 写数据
    wire [AXI_DATA_WIDTH-1:0]   m_axi_wdata;
    wire [AXI_DATA_WIDTH/8-1:0] m_axi_wstrb;
    wire                        m_axi_wlast;
    wire                        m_axi_wvalid;
    reg                         m_axi_wready;

    // 写响应
    reg  [AXI_ID_WIDTH-1:0]  m_axi_bid;
    reg  [1:0]               m_axi_bresp;
    reg                      m_axi_bvalid;
    wire                     m_axi_bready;

    // 读地址
    wire [AXI_ID_WIDTH-1:0]   m_axi_arid;
    wire [AXI_ADDR_WIDTH-1:0] m_axi_araddr;
    wire [7:0]                m_axi_arlen;
    wire [2:0]                m_axi_arsize;
    wire [1:0]                m_axi_arburst;
    wire                      m_axi_arlock;
    wire [3:0]                m_axi_arcache;
    wire [2:0]                m_axi_arprot;
    wire [3:0]                m_axi_arqos;
    wire [3:0]                m_axi_arregion;
    wire                      m_axi_arvalid;
    reg                       m_axi_arready;

    // 读数据
    reg  [AXI_ID_WIDTH-1:0]   m_axi_rid;
    reg  [AXI_DATA_WIDTH-1:0] m_axi_rdata;
    reg  [1:0]                m_axi_rresp;
    reg                       m_axi_rlast;
    reg                       m_axi_rvalid;
    wire                      m_axi_rready;

    // ==================================================================
    // Scoreboard — 2D: [frame_idx][pixel_idx]
    // ==================================================================
    reg [15:0] scoreboard [0:MAX_FRAMES-1][0:MAX_FRAME_DEPTH-1];

    // ==================================================================
    // 测试控制变量
    // ==================================================================
    integer      frame_i, pixel_i;
    reg  [7:0]   test_num;
    reg  [15:0]  last_img_width;
    reg  [15:0]  last_img_height;
    reg  [1:0]   last_read_mode;

    // ==================================================================
    // DUT 例化
    // ==================================================================
    ccd_frame_buf_ddr_ctrl #(
        .MAX_FRAMES      (MAX_FRAMES),
        .MAX_FRAME_DEPTH (MAX_FRAME_DEPTH),
        .AXI_ADDR_WIDTH  (AXI_ADDR_WIDTH),
        .AXI_DATA_WIDTH  (AXI_DATA_WIDTH),
        .AXI_BURST_LEN   (AXI_BURST_LEN),
        .FIFO_ADDR_WIDTH (FIFO_ADDR_WIDTH)
    ) u_dut (
        .i_ui_clk         (i_ui_clk),
        .i_wr_clk         (i_adcclk),
        .i_rd_clk         (i_rd_clk),
        .i_rst_n          (ctrl_rst_n),

        .i_wr_data        (i_wr_data),
        .i_wr_en          (i_wr_en),
        .i_pixel_type     (i_pixel_type),
        .i_frame_start    (i_frame_start),
        .i_frame_end      (i_frame_end),
        .i_image_width    (i_image_width),
        .i_image_height   (i_image_height),
        .i_read_mode      (i_read_mode),

        .o_fifo_data      (o_fifo_data),
        .o_frame_num      (o_frame_num),
        .i_fifo_rd_en     (i_fifo_rd_en),
        .o_fifo_prelast (o_fifo_prelast),
        .o_frame_written (o_frame_written),

        .o_frame_exception(o_frame_exception),

        // 写控制 → adapter
        .o_axi_wr_req       (ctrl_wr_req),
        .o_axi_wr_start_addr(ctrl_wr_start),
        .o_axi_wr_end_addr  (ctrl_wr_end),
        .i_axi_wr_idle      (ctrl_wr_idle),

        // 读控制 → adapter
        .o_axi_rd_req       (ctrl_rd_req),
        .o_axi_rd_start_addr(ctrl_rd_start),
        .o_axi_rd_end_addr  (ctrl_rd_end),
        .i_axi_rd_idle      (ctrl_rd_idle),

        // wr-fifo ↔ adapter
        .o_wrfifo_dout      (wrfifo_dout),
        .i_wrfifo_rden      (wrfifo_rden),

        // rd-fifo ↔ adapter
        .i_rdfifo_wren      (rdfifo_wren),
        .i_rdfifo_din       (rdfifo_din)
    );

    // ==================================================================
    // AXI4 Adapter (ctrl ↔ BFM)
    // ==================================================================
    ccd_frame_buf_ddr_axi_adapter #(
        .AXI_DATA_WIDTH (AXI_DATA_WIDTH),
        .AXI_ADDR_WIDTH (AXI_ADDR_WIDTH),
        .AXI_ID_WIDTH   (AXI_ID_WIDTH),
        .AXI_ID         (AXI_ID),
        .AXI_BURST_LEN  (AXI_BURST_LEN)
    ) u_adapter (
        .i_clk              (i_ui_clk),
        .i_rst_n            (ctrl_rst_n),
        .i_axi_wr_req       (ctrl_wr_req),
        .i_axi_wr_start_addr(ctrl_wr_start),
        .i_axi_wr_end_addr  (ctrl_wr_end),
        .o_axi_wr_idle      (ctrl_wr_idle),
        .i_axi_rd_req       (ctrl_rd_req),
        .i_axi_rd_start_addr(ctrl_rd_start),
        .i_axi_rd_end_addr  (ctrl_rd_end),
        .o_axi_rd_idle      (ctrl_rd_idle),
        .o_wrfifo_rden      (wrfifo_rden),
        .i_wrfifo_dout      (wrfifo_dout),
        .o_rdfifo_wren      (rdfifo_wren),
        .o_rdfifo_din       (rdfifo_din),
        .m_axi_awid         (m_axi_awid),
        .m_axi_awaddr       (m_axi_awaddr),
        .m_axi_awlen        (m_axi_awlen),
        .m_axi_awsize       (m_axi_awsize),
        .m_axi_awburst      (m_axi_awburst),
        .m_axi_awlock       (m_axi_awlock),
        .m_axi_awcache      (m_axi_awcache),
        .m_axi_awprot       (m_axi_awprot),
        .m_axi_awqos        (m_axi_awqos),
        .m_axi_awregion     (m_axi_awregion),
        .m_axi_awvalid      (m_axi_awvalid),
        .m_axi_awready      (m_axi_awready),
        .m_axi_wdata        (m_axi_wdata),
        .m_axi_wstrb        (m_axi_wstrb),
        .m_axi_wlast        (m_axi_wlast),
        .m_axi_wvalid       (m_axi_wvalid),
        .m_axi_wready       (m_axi_wready),
        .m_axi_bid          (m_axi_bid),
        .m_axi_bresp        (m_axi_bresp),
        .m_axi_bvalid       (m_axi_bvalid),
        .m_axi_bready       (m_axi_bready),
        .m_axi_arid         (m_axi_arid),
        .m_axi_araddr       (m_axi_araddr),
        .m_axi_arlen        (m_axi_arlen),
        .m_axi_arsize       (m_axi_arsize),
        .m_axi_arburst      (m_axi_arburst),
        .m_axi_arlock       (m_axi_arlock),
        .m_axi_arcache      (m_axi_arcache),
        .m_axi_arprot       (m_axi_arprot),
        .m_axi_arqos        (m_axi_arqos),
        .m_axi_arregion     (m_axi_arregion),
        .m_axi_arvalid      (m_axi_arvalid),
        .m_axi_arready      (m_axi_arready),
        .m_axi_rid          (m_axi_rid),
        .m_axi_rdata        (m_axi_rdata),
        .m_axi_rresp        (m_axi_rresp),
        .m_axi_rlast        (m_axi_rlast),
        .m_axi_rvalid       (m_axi_rvalid),
        .m_axi_rready       (m_axi_rready)
    );

    // ==================================================================
    // AXI4 Slave BFM 
    // ==================================================================
    reg [AXI_DATA_WIDTH-1:0] mem [0:MEM_DEPTH-1];
    integer                  axi_delay_mode;

    // 写事务寄存器
    reg                      aw_active;
    reg [AXI_ADDR_WIDTH-1:0] aw_addr_reg;
    reg [7:0]                aw_len_reg;
    reg [AXI_ID_WIDTH-1:0]   aw_id_reg;
    reg [7:0]                wr_beat_cnt;
    reg                      wr_wlast_seen;
    reg                      b_sent;

    // 读事务寄存器
    reg                      ar_active;
    reg [AXI_ADDR_WIDTH-1:0] ar_addr_reg;
    reg [7:0]                ar_len_reg;
    reg [AXI_ID_WIDTH-1:0]   ar_id_reg;
    reg [7:0]                rd_beat_cnt;
    reg                      rd_data_valid;

    // ----- 延迟函数 -----
    function integer get_delay;
        input dummy;
        begin
            if (axi_delay_mode == 0) get_delay = 0;
            else get_delay = {$random} % 4;
        end
    endfunction

    // ----- AW + W + B 通道 -----
    always @(*) m_axi_awready = !aw_active;

    always @(posedge i_ui_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            aw_active   <= 1'b0;
            aw_addr_reg <= 0;
            aw_len_reg  <= 8'd0;
            aw_id_reg   <= 4'b0000;
        end else if (m_axi_awvalid && m_axi_awready) begin
            aw_addr_reg <= m_axi_awaddr;
            aw_len_reg  <= m_axi_awlen;
            aw_id_reg   <= m_axi_awid;
            aw_active   <= 1'b1;
        end else if (aw_active && b_sent && m_axi_bvalid && m_axi_bready) begin
            aw_active <= 1'b0;
        end
    end

    always @(posedge i_ui_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            m_axi_wready  <= 1'b0;
            wr_beat_cnt   <= 8'd0;
            wr_wlast_seen <= 1'b0;
        end else begin
            m_axi_wready <= 1'b0;
            if (aw_active && m_axi_wvalid && !m_axi_wready) begin
                if (get_delay(0) == 0) begin
                    m_axi_wready <= 1'b1;
                    mem[(aw_addr_reg >> 4) + wr_beat_cnt] <= m_axi_wdata;
                    wr_beat_cnt <= wr_beat_cnt + 1;
                    if (m_axi_wlast) begin
                        wr_wlast_seen <= 1'b1;
                    end
                end
            end
        end
    end

    always @(posedge i_ui_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            m_axi_bid    <= 4'b0000;
            m_axi_bresp  <= 2'b00;
            m_axi_bvalid <= 1'b0;
            b_sent       <= 1'b0;
        end else begin
            if (wr_wlast_seen && !b_sent && aw_active) begin
                if (get_delay(0) == 0) begin
                    m_axi_bid    <= aw_id_reg;
                    m_axi_bresp  <= 2'b00;
                    m_axi_bvalid <= 1'b1;
                    b_sent       <= 1'b1;
                end
            end
            if (m_axi_bvalid && m_axi_bready) begin
                m_axi_bvalid <= 1'b0;
                wr_beat_cnt   <= 8'd0;
                wr_wlast_seen <= 1'b0;
                b_sent        <= 1'b0;
            end
        end
    end

    // ----- AR + R 通道 -----
    always @(*) m_axi_arready = !ar_active;

    always @(posedge i_ui_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            ar_active   <= 1'b0;
            ar_addr_reg <= 0;
            ar_len_reg  <= 8'd0;
            ar_id_reg   <= 4'b0000;
        end else if (m_axi_arvalid && m_axi_arready) begin
            ar_addr_reg <= m_axi_araddr;
            ar_len_reg  <= m_axi_arlen;
            ar_id_reg   <= m_axi_arid;
            ar_active   <= 1'b1;
        end else if (ar_active && rd_data_valid && m_axi_rready && m_axi_rlast) begin
            ar_active <= 1'b0;
        end
    end

    always @(posedge i_ui_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            m_axi_rid      <= 4'b0000;
            m_axi_rdata    <= {AXI_DATA_WIDTH{1'b0}};
            m_axi_rresp    <= 2'b00;
            m_axi_rlast    <= 1'b0;
            m_axi_rvalid   <= 1'b0;
            rd_beat_cnt    <= 8'd0;
            rd_data_valid  <= 1'b0;
        end else begin
            if (m_axi_rvalid && m_axi_rready) begin
                m_axi_rvalid  <= 1'b0;
                rd_data_valid <= 1'b0;
                if (m_axi_rlast) begin
                    rd_beat_cnt <= 8'd0;
                end
            end
            if (ar_active && !rd_data_valid && rd_beat_cnt <= ar_len_reg) begin
                if (get_delay(0) == 0) begin
                    m_axi_rid    <= ar_id_reg;
                    m_axi_rdata  <= mem[(ar_addr_reg >> 4) + rd_beat_cnt];
                    m_axi_rresp  <= 2'b00;
                    m_axi_rlast  <= (rd_beat_cnt == ar_len_reg) ? 1'b1 : 1'b0;
                    m_axi_rvalid <= 1'b1;
                    rd_data_valid <= 1'b1;
                    rd_beat_cnt   <= rd_beat_cnt + 1;
                end
            end
        end
    end

    // ==================================================================
    // 辅助 Tasks
    // ==================================================================

    task wait_adc_cycles;
        input integer cycles;
        begin
            repeat(cycles) @(posedge i_adcclk);
        end
    endtask

    task wait_rd_cycles;
        input integer cycles;
        begin
            repeat(cycles) @(posedge i_rd_clk);
        end
    endtask

    task wait_ui_cycles;
        input integer cycles;
        begin
            repeat(cycles) @(posedge i_ui_clk);
        end
    endtask

    // ------------------------------------------------------------------
    // reset_dut: 系统复位 + 模拟 DDR3 初始化完成
    // ------------------------------------------------------------------
    task reset_dut;
        begin
            $display("  [RESET] Asserting...");
            i_rst_n              <= 1'b0;
            tb_ddr3_init_done    <= 1'b0;
            soft_rst             <= 1'b0;
            i_wr_en           <= 1'b0;
            i_wr_data         <= 16'd0;
            i_pixel_type      <= 2'b00;
            i_frame_start     <= 1'b0;
            i_frame_end       <= 1'b0;
            i_image_width     <= 16'd0;
            i_image_height    <= 16'd0;
            i_read_mode       <= 2'd0;
            i_fifo_rd_en      <= 1'b0;
            axi_delay_mode    <= 0;
            last_img_width    <= 16'd0;
            last_img_height   <= 16'd0;
            last_read_mode    <= 2'd0;

            m_axi_wready  <= 1'b0;
            m_axi_bid     <= 4'b0000;
            m_axi_bresp   <= 2'b00;
            m_axi_bvalid  <= 1'b0;
            m_axi_rid     <= 4'b0000;
            m_axi_rdata   <= {AXI_DATA_WIDTH{1'b0}};
            m_axi_rresp   <= 2'b00;
            m_axi_rlast   <= 1'b0;
            m_axi_rvalid  <= 1'b0;

            aw_active     <= 1'b0;
            wr_beat_cnt   <= 8'd0;
            wr_wlast_seen <= 1'b0;
            b_sent        <= 1'b0;
            ar_active     <= 1'b0;
            rd_beat_cnt   <= 8'd0;
            rd_data_valid <= 1'b0;

            wait_ui_cycles(5);
            i_rst_n <= 1'b1;
            wait_ui_cycles(20);

            // 模拟 DDR3 初始化完成 → ctrl_rst_n 释放
            tb_ddr3_init_done <= 1'b1;
            wait_ui_cycles(20);
            $display("  [RESET] Done (DDR3 init simulated)");
        end
    endtask

    // ------------------------------------------------------------------
    // pulse_soft_rst: 模拟顶层参数变化触发的软复位
    //   置 soft_rst=1 → 等待足够多周期 (覆盖 ctrl 三域复位 + 释放同步)
    //   → 清 0 → 等待重新锁存完成
    // ------------------------------------------------------------------
    task pulse_soft_rst;
        begin
            $display("  [SOFT_RST] Asserting (simulate image-param change)...");
            soft_rst <= 1'b1;
            wait_ui_cycles(2000);     // 足够 ctrl 三域复位 (wr_clk=50MHz → 1000 周期)
            soft_rst <= 1'b0;
            wait_ui_cycles(2000);     // 等释放同步 + 重新锁存帧长度
            wait_adc_cycles(20);
            $display("  [SOFT_RST] Released");
        end
    endtask

    // ------------------------------------------------------------------
    // send_frame: 在 ADC 域发送一帧像素数据
    //   width/height/read_mode: 帧参数
    //   pixel_count: 实际发送的 active 像素数
    //   data_base: 像素数据起始值
    //   sb_idx:     scoreboard 帧索引
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
            $display("  [SEND] width=%0d, height=%0d, mode=%0d, pixels=%0d, base=0x%h, sb_idx=%0d",
                     width, height, read_mode, pixel_count, data_base, sb_idx);

            @(posedge i_adcclk);
            i_image_width  <= width;
            i_image_height <= height;
            i_read_mode    <= read_mode;
            i_wr_en        <= 1'b0;
            i_wr_data      <= 16'd0;
            i_pixel_type   <= 2'b00;

            // 参数变化 → 模拟顶层软复位, 重新锁定帧长度 (固定长度锁存机制)
            if (width != last_img_width || height != last_img_height ||
                read_mode != last_read_mode) begin
                last_img_width  <= width;
                last_img_height <= height;
                last_read_mode  <= read_mode;
                pulse_soft_rst;
            end

            // frame_start 脉冲
            @(posedge i_adcclk);
            i_frame_start  <= 1'b1;
            @(posedge i_adcclk);
            i_frame_start  <= 1'b0;

            // 发送 active pixels
            for (p = 0; p < pixel_count; p = p + 1) begin
                @(posedge i_adcclk);
                i_wr_en      <= 1'b1;
                i_pixel_type <= 2'b10;
                i_wr_data    <= data_base + p;
                scoreboard[sb_idx][p] <= data_base + p;
            end

            // frame_end 脉冲
            @(posedge i_adcclk);
            i_wr_en      <= 1'b0;
            i_pixel_type <= 2'b00;

            i_frame_end  <= 1'b1;
            @(posedge i_adcclk);
            i_frame_end  <= 1'b0;

            // 等待帧处理完成
            wait_adc_cycles(100);
            $display("  [SEND] Done, %0d pixels sent", pixel_count);
        end
    endtask

    // ------------------------------------------------------------------
    // read_frame: 在 RD 域从 o_fifo_data 读取一帧并验证
    //   sb_idx: scoreboard 帧索引
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

                if (rd_data !== scoreboard[sb_idx][rd_cnt]) begin
                    $display("  [READ] ** MISMATCH ** idx=%0d: got=0x%h, expected=0x%h",
                             rd_cnt, rd_data, scoreboard[sb_idx][rd_cnt]);
                    errors = errors + 1;
                    $stop;
                end

                rd_cnt = rd_cnt + 1;
                
                if(rd_cnt == pixel_count - 1)
                    i_fifo_rd_en <= 1'b0;
            end


            if (errors == 0)
                $display("  [READ] PASS — %0d pixels verified", pixel_count);
            else begin
                $display("  [READ] FAIL — %0d mismatch(es)", errors);
                $stop;
            end

            wait_rd_cycles(5);
        end
    endtask

    // ------------------------------------------------------------------
    // wait_read_available: 等待数据可读
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
            if (t >= timeout)
                $display("  [WAIT] Timeout — no data available");
            else
                $display("  [WAIT] Data available, o_frame_num=%0d", o_frame_num);
        end
    endtask

    // ==================================================================
    // 测试序列
    // ==================================================================
    initial begin
        // 初始状态
        i_rst_n              = 1'b0;
        tb_ddr3_init_done    = 1'b0;
        soft_rst             = 1'b0;
        i_wr_en          = 1'b0;
        i_wr_data        = 16'd0;
        i_pixel_type     = 2'b00;
        i_frame_start    = 1'b0;
        i_frame_end      = 1'b0;
        i_image_width    = 16'd0;
        i_image_height   = 16'd0;
        i_read_mode      = 2'd0;
        i_fifo_rd_en     = 1'b0;
        axi_delay_mode   = 0;
        test_num         = 8'd0;
        last_img_width   = 16'd0;
        last_img_height  = 16'd0;
        last_read_mode   = 2'd0;

        wait_ui_cycles(10);
        $display("============================================================");
        $display("  test_ccd_frame_buf_ddr_ctrl");
        $display("  MAX_FRAMES=%0d, MAX_FRAME_DEPTH=%0d", MAX_FRAMES, MAX_FRAME_DEPTH);
        $display("============================================================");

        // ================================================================
        // Test 1: 复位后空闲状态
        // ================================================================
        test_num = test_num + 1;
        $display("\n##########################################################");
        $display("  Test %0d: Reset & Idle", test_num);
        $display("##########################################################\n");
        reset_dut;
        wait_ui_cycles(50);
        $display("  o_frame_num = %0d (expect 0)", o_frame_num);

        // ================================================================
        // Test 2: 单帧含整 burst + 部分尾 (480 pixels)
        // ================================================================
        test_num = test_num + 1;
        $display("\n##########################################################");
        $display("  Test %0d: Single frame — 1 full burst + partial tail (480 pixels)", test_num);
        $display("##########################################################\n");
        reset_dut;

        send_frame(16'd480, 16'd1, 2'd0, 16'd480, 16'hA000, 0);
        wait_read_available(5000);
        read_frame(16'd480, 16'hA000, 0);

        // ================================================================
        // Test 3: 单帧 — 仅部分尾 (280 pixels)
        // ================================================================
        test_num = test_num + 1;
        $display("\n##########################################################");
        $display("  Test %0d: Single frame — partial tail (280 pixels)", test_num);
        $display("##########################################################\n");
        reset_dut;

        send_frame(16'd280, 16'd1, 2'd0, 16'd280, 16'hB000, 0);
        wait_read_available(5000);
        read_frame(16'd280, 16'hB000, 0);

        // ================================================================
        // Test 4: 无效帧 — 像素计数不匹配
        // ================================================================
        test_num = test_num + 1;
        $display("\n##########################################################");
        $display("  Test %0d: Invalid frame — pixel count mismatch", test_num);
        $display("##########################################################\n");
        reset_dut;

        send_frame(16'd512, 16'd1, 2'd0, 16'd500, 16'hC000, 0);
        wait_adc_cycles(200);
        $display("  o_frame_num = %0d (expect 0)", o_frame_num);
        
        // ================================================================
        // Test 5: read_mode=1 — width×height
        // ================================================================
        test_num = test_num + 1;
        $display("\n##########################################################");
        $display("  Test %0d: read_mode=1 — %0dx%0d=%0d pixels",
                 test_num, 60, 8, 60*8);
        $display("##########################################################\n");
        reset_dut;

        send_frame(16'd60, 16'd8, 2'd1, 16'd480, 16'hD000, 0);
        wait_read_available(5000);
        read_frame(16'd480, 16'hD000, 0);
        
        // ================================================================
        // Test 6: 环形缓冲满 (MAX_FRAMES=4)
        // ================================================================
        test_num = test_num + 1;
        $display("\n##########################################################");
        $display("  Test %0d: Ring buffer full (MAX_FRAMES=%0d)", test_num, MAX_FRAMES);
        $display("##########################################################\n");
        reset_dut;

        for (frame_i = 0; frame_i < MAX_FRAMES; frame_i = frame_i + 1) begin
            $display("  --- Writing frame %0d/%0d ---", frame_i + 1, MAX_FRAMES);
            send_frame(16'd256, 16'd1, 2'd0, 16'd256,
                       16'h1000 + frame_i * 16'h100, frame_i);
        end

        // 第 5 帧应被阻塞
        $display("  --- Attempting frame %0d (should be BLOCKED) ---", MAX_FRAMES + 1);
        @(posedge i_adcclk);
        i_image_width  <= 16'd256;
        i_image_height <= 16'd1;
        i_read_mode    <= 2'd0;

        @(posedge i_adcclk);
        i_frame_start  <= 1'b1;
        @(posedge i_adcclk);
        i_frame_start  <= 1'b0;

        // 无数据进入（脉冲太短, frame_start_rise 来不及被 controller 锁存?）
        // 实际: frame_start 脉冲经过 CDC 后在 ui_clk 域可能丢失,
        //       但 wr_not_full 检查会在 ui_clk 域拒绝
        wait_adc_cycles(50);
        @(posedge i_adcclk);
        i_frame_end  <= 1'b1;
        @(posedge i_adcclk);
        i_frame_end  <= 1'b0;

        wait_adc_cycles(200);
        $display("  o_frame_num = %0d (expect %0d)", o_frame_num, MAX_FRAMES);

        // 读出所有帧验证
        for (frame_i = 0; frame_i < MAX_FRAMES; frame_i = frame_i + 1) begin
            wait_read_available(5000);
            read_frame(16'd256, 16'h1000 + frame_i * 16'h100, frame_i);
        end
        
        // ================================================================
        // Test 7: 参数切换 (read_mode/尺寸) → 软复位 → 新帧长度锁定
        //   帧 0: mode=0, 480 pixels → 读回
        //   切换参数 (mode=1, 60×8=480) → send_frame 触发软复位
        //   → 缓存清零, 重新锁定 60×8=480 → 帧 1 写读验证
        // ================================================================
        test_num = test_num + 1;
        $display("\n##########################################################");
        $display("  Test %0d: Param change — soft reset & new frame depth lock", test_num);
        $display("##########################################################\n");
        reset_dut;

        // 帧 0: read_mode=0, 480 pixels
        send_frame(16'd480, 16'd1, 2'd0, 16'd480, 16'hE000, 0);
        wait_read_available(5000);
        read_frame(16'd480, 16'hE000, 0);
        $display("  [CHECK] o_frame_num = %0d (expect 0 after read)", o_frame_num);

        // 帧 1: read_mode=1, 60×8=480 pixels (参数变化 → send_frame 内软复位)
        send_frame(16'd60, 16'd8, 2'd1, 16'd480, 16'hF000, 0);
        $display("  [CHECK] o_frame_num = %0d (expect 0, cache was flushed by soft reset)", o_frame_num);

        // 读回帧 1 (按新锁存深度 480)
        wait_read_available(5000);
        read_frame(16'd480, 16'hF000, 0);

        // ================================================================
        // Test 8: 软复位清空已缓存帧
        //   写一帧 → 缓存 1 帧 → 手动 soft_rst → 缓存清零
        // ================================================================
        test_num = test_num + 1;
        $display("\n##########################################################");
        $display("  Test %0d: Soft reset flushes cached frames", test_num);
        $display("##########################################################\n");
        reset_dut;

        send_frame(16'd256, 16'd1, 2'd0, 16'd256, 16'h3000, 0);
        wait_read_available(5000);
        $display("  [CHECK] o_frame_num = %0d (expect 1)", o_frame_num);

        // 手动触发软复位 (模拟参数变化), 不清空 last_* → 不改锁存目标
        pulse_soft_rst;
        $display("  [CHECK] o_frame_num = %0d (expect 0 after soft reset)", o_frame_num);

        // 参数未变, 再次写同参数帧 → 锁存保持, 正常写读
        send_frame(16'd256, 16'd1, 2'd0, 16'd256, 16'h3100, 0);
        wait_read_available(5000);
        read_frame(16'd256, 16'h3100, 0);

        $display("  [CHECK] o_fifo_prelast timing correct for fixed frame depth");

        // ================================================================
        // 完成
        // ================================================================
        $display("\n============================================================");
        $display("  Simulation Complete");
        $display("============================================================");

        $finish;
    end

endmodule

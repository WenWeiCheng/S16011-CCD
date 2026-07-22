`timescale 1ns / 1ps
//==============================================================================
// Testbench : test_ccd_frame_buf_ddr_axi_adapter
// Desc      : ccd_frame_buf_ddr_axi_adapter 的独立 testbench
//            内置 AXI4 Slave BFM (2 周期握手), 简单寄存器 FIFO 模型
//==============================================================================
module test_ccd_frame_buf_ddr_axi_adapter;

    localparam AXI_DATA_WIDTH  = 128;
    localparam AXI_ADDR_WIDTH  = 30;
    localparam AXI_ID_WIDTH    = 4;
    localparam AXI_ID          = 4'b0000;
    localparam AXI_BURST_LEN   = 8'd31;
    localparam BURST_BEATS     = AXI_BURST_LEN + 1;
    localparam CLK_PERIOD      = 10;
    localparam MEM_DEPTH       = 16384;

    reg i_clk;
    reg i_rst_n;
    initial i_clk = 1'b0;
    always #(CLK_PERIOD/2) i_clk = ~i_clk;

    //==========================================================================
    // Controller 接口 (驱动 DUT)
    //==========================================================================
    reg                       i_axi_wr_req;
    reg  [AXI_ADDR_WIDTH-1:0] i_axi_wr_start_addr;
    reg  [AXI_ADDR_WIDTH-1:0] i_axi_wr_end_addr;
    wire                      o_axi_wr_idle;

    reg                       i_axi_rd_req;
    reg  [AXI_ADDR_WIDTH-1:0] i_axi_rd_start_addr;
    reg  [AXI_ADDR_WIDTH-1:0] i_axi_rd_end_addr;
    wire                      o_axi_rd_idle;

    //==========================================================================
    // FIFO 接口 (连接 DUT)
    //==========================================================================
    wire                      o_wrfifo_rden;
    reg  [AXI_DATA_WIDTH-1:0] i_wrfifo_dout;

    wire                      o_rdfifo_wren;
    wire [AXI_DATA_WIDTH-1:0] o_rdfifo_din;

    //==========================================================================
    // AXI4 信号
    //==========================================================================
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

    wire [AXI_DATA_WIDTH-1:0] m_axi_wdata;
    wire [AXI_DATA_WIDTH/8-1:0] m_axi_wstrb;
    wire                      m_axi_wlast;
    wire                      m_axi_wvalid;
    reg                       m_axi_wready;

    reg  [AXI_ID_WIDTH-1:0]  m_axi_bid;
    reg  [1:0]               m_axi_bresp;
    reg                      m_axi_bvalid;
    wire                     m_axi_bready;

    wire [AXI_ID_WIDTH-1:0]  m_axi_arid;
    wire [AXI_ADDR_WIDTH-1:0] m_axi_araddr;
    wire [7:0]               m_axi_arlen;
    wire [2:0]               m_axi_arsize;
    wire [1:0]               m_axi_arburst;
    wire                      m_axi_arlock;
    wire [3:0]                m_axi_arcache;
    wire [2:0]                m_axi_arprot;
    wire [3:0]                m_axi_arqos;
    wire [3:0]                m_axi_arregion;
    wire                      m_axi_arvalid;
    reg                      m_axi_arready;

    reg  [AXI_ID_WIDTH-1:0]  m_axi_rid;
    reg  [AXI_DATA_WIDTH-1:0] m_axi_rdata;
    reg  [1:0]               m_axi_rresp;
    reg                      m_axi_rlast;
    reg                      m_axi_rvalid;
    wire                     m_axi_rready;

    //==========================================================================
    // 内存模型 & BFM 寄存器
    //==========================================================================
    reg [AXI_DATA_WIDTH-1:0] mem [0:MEM_DEPTH-1];

    // 写事务 (AW+W+B) 寄存器
    reg                      aw_active;
    reg [AXI_ADDR_WIDTH-1:0] aw_addr_reg;
    reg [7:0]                aw_len_reg;
    reg [AXI_ID_WIDTH-1:0]   aw_id_reg;
    reg [7:0]                wr_beat_cnt;
    reg                      wr_wlast_seen;
    reg                      b_sent;

    // 读事务 (AR+R) 寄存器
    reg                      ar_active;
    reg [AXI_ADDR_WIDTH-1:0] ar_addr_reg;
    reg [7:0]                ar_len_reg;
    reg [AXI_ID_WIDTH-1:0]   ar_id_reg;
    reg [7:0]                rd_beat_cnt;
    reg                      rd_data_valid;

    integer axi_delay_mode;

    //==========================================================================
    // DUT 例化
    //==========================================================================
    ccd_frame_buf_ddr_axi_adapter #(
        .AXI_DATA_WIDTH (AXI_DATA_WIDTH),
        .AXI_ADDR_WIDTH (AXI_ADDR_WIDTH),
        .AXI_ID_WIDTH   (AXI_ID_WIDTH),
        .AXI_ID         (AXI_ID),
        .AXI_BURST_LEN  (AXI_BURST_LEN)
    ) dut (
        .i_clk              (i_clk),
        .i_rst_n            (i_rst_n),
        .i_axi_wr_req       (i_axi_wr_req),
        .i_axi_wr_start_addr(i_axi_wr_start_addr),
        .i_axi_wr_end_addr  (i_axi_wr_end_addr),
        .o_axi_wr_idle      (o_axi_wr_idle),
        .i_axi_rd_req       (i_axi_rd_req),
        .i_axi_rd_start_addr(i_axi_rd_start_addr),
        .i_axi_rd_end_addr  (i_axi_rd_end_addr),
        .o_axi_rd_idle      (o_axi_rd_idle),
        .o_wrfifo_rden      (o_wrfifo_rden),
        .i_wrfifo_dout      (i_wrfifo_dout),
        .o_rdfifo_wren      (o_rdfifo_wren),
        .o_rdfifo_din       (o_rdfifo_din),
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

    //==========================================================================
    // Wr-fifo 模型: DUT 读 wrfifo 时提供 128-bit 数据
    //==========================================================================
    reg [AXI_DATA_WIDTH-1:0] wrfifo_data_q [0:65535];
    integer                  wrfifo_depth;
    integer                  wrfifo_rd_ptr;

    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            i_wrfifo_dout <= {AXI_DATA_WIDTH{1'b0}};
            wrfifo_rd_ptr <= 0;
        end else if (o_wrfifo_rden) begin
            if (wrfifo_rd_ptr < wrfifo_depth) begin
                i_wrfifo_dout <= wrfifo_data_q[wrfifo_rd_ptr];
                wrfifo_rd_ptr <= wrfifo_rd_ptr + 1;
            end else begin
                i_wrfifo_dout <= {AXI_DATA_WIDTH{1'bx}};
            end
        end
    end

    //==========================================================================
    // Rd-fifo 模型: 捕获 DUT 写回的 128-bit 数据
    //==========================================================================
    reg [AXI_DATA_WIDTH-1:0] rdfifo_data_q [0:65535];
    integer                  rdfifo_wr_ptr;

    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            rdfifo_wr_ptr <= 0;
        end else if (o_rdfifo_wren) begin
            rdfifo_data_q[rdfifo_wr_ptr] <= o_rdfifo_din;
            rdfifo_wr_ptr <= rdfifo_wr_ptr + 1;
        end
    end

    //==========================================================================
    // AXI4 Slave BFM — 缓冲器分离架构
    //==========================================================================
    // 参考 EasyAXI 的 buffer 分离思想:
    //   地址通道 (AW/AR): 用 active 标志控制 ready, 握手时捕获 payload
    //   数据通道 (W/R):  基于捕获的 payload 驱动数据传输和 beat 计数
    //   响应通道 (B):    写完成后自动发送 bvalid
    //
    // 每通道的 ready 是组合逻辑: ready = !active (空闲时才接收新请求)
    // 地址捕获和数据处理分离在不同 always 块中。

    // 延迟模式: 0=零延迟, 1=插入 0~3 拍随机延迟

    function integer get_delay;
        input dummy;
        begin
            if (axi_delay_mode == 0) get_delay = 0;
            else get_delay = {$random} % 4;
        end
    endfunction

    //--------------------------------------------------------------------------
    // AW + W + B 通道 (写事务)
    //--------------------------------------------------------------------------
    // AW ready: 仅当空闲时才 ready
    always @(*) m_axi_awready = !aw_active;

    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            aw_active   <= 1'b0;
            aw_addr_reg <= 0;
            aw_len_reg  <= 8'd0;
            aw_id_reg   <= 4'b0000;
        end else if (m_axi_awvalid && m_axi_awready) begin
            // 握手完成: 捕获地址/len/id, 激活写事务
            aw_addr_reg <= m_axi_awaddr;
            aw_len_reg  <= m_axi_awlen;
            aw_id_reg   <= m_axi_awid;
            aw_active   <= 1'b1;
        end else if (aw_active && b_sent && m_axi_bvalid && m_axi_bready) begin
            // B 响应握手完成, 清除 active
            aw_active <= 1'b0;
        end
    end

    // W 通道: 写入数据到 mem
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            m_axi_wready  <= 1'b0;
            wr_beat_cnt   <= 8'd0;
            wr_wlast_seen <= 1'b0;
        end else begin
            m_axi_wready <= 1'b0;
            if (aw_active && m_axi_wvalid && !m_axi_wready) begin
                // 延迟拍数后 ready
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

    // B 通道: wlast 后发送写响应
    always @(posedge i_clk or negedge i_rst_n) begin
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

    //--------------------------------------------------------------------------
    // AR + R 通道 (读事务)
    //--------------------------------------------------------------------------

    // AR ready: 仅当空闲时才 ready
    always @(*) m_axi_arready = !ar_active;

    always @(posedge i_clk or negedge i_rst_n) begin
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
            // 最后一拍握手完成, 清除 active
            ar_active <= 1'b0;
        end
    end

    // R 通道: 发送读数据
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            m_axi_rid      <= 4'b0000;
            m_axi_rdata    <= {AXI_DATA_WIDTH{1'b0}};
            m_axi_rresp    <= 2'b00;
            m_axi_rlast    <= 1'b0;
            m_axi_rvalid   <= 1'b0;
            rd_beat_cnt    <= 8'd0;
            rd_data_valid  <= 1'b0;
        end else begin
            // 当前拍已握手完成 → 清除 valid
            if (m_axi_rvalid && m_axi_rready) begin
                m_axi_rvalid  <= 1'b0;
                rd_data_valid <= 1'b0;
                if (m_axi_rlast) begin
                    rd_beat_cnt <= 8'd0;
                end
            end

            // 空闲且事务活跃 → 发送下一拍
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

    //==========================================================================
    // 测试辅助
    //==========================================================================
    task wait_cycles;
        input integer cycles;
        begin
            repeat(cycles) @(posedge i_clk);
        end
    endtask

    // 预载 wrfifo 数据 (128-bit 递增)
    task load_wrfifo;
        input [AXI_ADDR_WIDTH-1:0] base;
        input integer              count;
        integer i;
        begin
            wrfifo_depth = count;
            wrfifo_rd_ptr = 0;
            for (i = 0; i < count; i = i + 1) begin
                wrfifo_data_q[i] = {{64{1'b0}}, 64'd0} | (base + i);
            end
            $display("  [WRFIFO] Loaded %0d words, base=0x%h", count, base);
        end
    endtask

    task axi_write;
        input  [AXI_ADDR_WIDTH-1:0] start_addr;
        input  [AXI_ADDR_WIDTH-1:0] end_addr;
        begin
            $display("----------------------------------------");
            $display("[WRITE] start=0x%h, end=0x%h", start_addr, end_addr);

            #1;
            while (!o_axi_wr_idle) @(posedge i_clk); #1;

            i_axi_wr_start_addr <= start_addr;
            i_axi_wr_end_addr   <= end_addr;
            i_axi_wr_req        <= 1'b1;
            @(posedge i_clk);
            i_axi_wr_req        <= 1'b0;
            // wait to start
            wait(!o_axi_wr_idle);
            // wait to cplt
            while (!o_axi_wr_idle) @(posedge i_clk);
            $display("  [WRITE] Done.");
            $display("----------------------------------------\n");
        end
    endtask

    task axi_read;
        input  [AXI_ADDR_WIDTH-1:0] start_addr;
        input  [AXI_ADDR_WIDTH-1:0] end_addr;
        begin
            $display("----------------------------------------");
            $display("[READ]  start=0x%h, end=0x%h", start_addr, end_addr);

            while (!o_axi_rd_idle) @(posedge i_clk);

            i_axi_rd_start_addr <= start_addr;
            i_axi_rd_end_addr   <= end_addr;
            i_axi_rd_req        <= 1'b1;
            @(posedge i_clk);
            i_axi_rd_req        <= 1'b0;
            // wait to start
            wait(!o_axi_rd_idle);
            // wait to cplt
            while (!o_axi_rd_idle) @(posedge i_clk); #1;
            $display("  [READ] Done. (rdfifo has %0d words)", rdfifo_wr_ptr);
            $display("----------------------------------------\n");
        end
    endtask

    task reset_dut;
        begin
            $display("=== Reset ===");
            aw_active       <= 1'b0;
            wr_beat_cnt     <= 8'd0;
            wr_wlast_seen   <= 1'b0;
            b_sent          <= 1'b0;
            ar_active       <= 1'b0;
            rd_beat_cnt     <= 8'd0;
            rd_data_valid   <= 1'b0;
            wrfifo_rd_ptr   <= 0;
            rdfifo_wr_ptr   <= 0;

            i_rst_n <= 1'b0;
            i_axi_wr_req  <= 1'b0;
            i_axi_rd_req  <= 1'b0;
            i_wrfifo_dout <= {AXI_DATA_WIDTH{1'b0}};
            wait_cycles(10);
            i_rst_n <= 1'b1;
            wait_cycles(20);
            $display("=== Reset Done ===\n");
        end
    endtask

    //==========================================================================
    // 测试序列
    //==========================================================================
    initial begin
        i_rst_n       <= 1'b0;
        i_axi_wr_req  <= 1'b0;
        i_axi_rd_req  <= 1'b0;
        i_wrfifo_dout <= {AXI_DATA_WIDTH{1'b0}};

        m_axi_wready  <= 1'b0;
        m_axi_bid     <= 4'b0000;
        m_axi_bresp   <= 2'b00;
        m_axi_bvalid  <= 1'b0;
        m_axi_rid     <= 4'b0000;
        m_axi_rdata   <= {AXI_DATA_WIDTH{1'b0}};
        m_axi_rresp   <= 2'b00;
        m_axi_rlast   <= 1'b0;
        m_axi_rvalid  <= 1'b0;

        axi_delay_mode <= 0;
        wrfifo_rd_ptr <= 0;
        rdfifo_wr_ptr <= 0;

        wait_cycles(10);
        $display("============================================================");
        $display("  test_ccd_frame_buf_ddr_axi_adapter");
        $display("============================================================");

        // Test 1: 写 32 beats
        $display("\n=== Test 1: Write 32 beats ===");
        reset_dut;
        load_wrfifo(32'h0000_0100, BURST_BEATS);
        axi_write(32'h0000_0000, 32'h0000_0200);

        // Test 2: 读 32 beats
        $display("\n=== Test 2: Read 32 beats ===");
        axi_read(32'h0000_0000, 32'h0000_0200);

        // Test 3: 随机延迟
        $display("\n=== Test 3: Random delay ===");
        axi_delay_mode <= 1;
        reset_dut;
        load_wrfifo(32'h0000_0200, BURST_BEATS);
        axi_write(32'h0000_1000, 32'h0000_1200);
        axi_read(32'h0000_1000, 32'h0000_1200);

        // Test 4: 短 burst
        $display("\n=== Test 4: Short burst (8 beats) ===");
        axi_delay_mode <= 0;
        reset_dut;
        load_wrfifo(32'h0000_0300, 8);
        axi_write(32'h0000_2000, 32'h0000_2080);
        axi_read(32'h0000_2000, 32'h0000_2080);

        // Test 5: 连续两次写
        $display("\n=== Test 5: Back-to-back writes ===");
        axi_delay_mode <= 0;
        reset_dut;
        load_wrfifo(32'h0000_0400, BURST_BEATS);
        axi_write(32'h0000_4000, 32'h0000_4200);
        load_wrfifo(32'h0000_0500, BURST_BEATS);
        axi_write(32'h0000_5000, 32'h0000_5200);
        axi_read(32'h0000_4000, 32'h0000_4200);
        axi_read(32'h0000_5000, 32'h0000_5200);

        $display("\n============================================================");
        $display("  Simulation Complete");
        $display("============================================================");

        #200;
        $finish;
    end

endmodule

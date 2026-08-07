
`timescale 1 ns / 1 ps

	module ccd_controller_v1_0_S00_AXI #
	(
		// Users to add parameters here
		parameter integer MAX_FRAME_DEPTH = 131072,
		parameter integer MAX_FRAMES      = 64,
		// User parameters ends
		// Do not modify the parameters beyond this line

		// Width of S_AXI data bus
		parameter integer C_S_AXI_DATA_WIDTH	= 32,
		// Width of S_AXI address bus
		parameter integer C_S_AXI_ADDR_WIDTH	= 6
	)
	(
		// Users to add ports here

		// 中断
		output wire         intr,

		// CCD 驱动信号
		output wire         o_adcclk,
		output wire         o_p1v,
		output wire         o_p2v_tg,
		output wire         o_p1h,
		output wire         o_p2h,
		output wire         o_p3h,
		output wire         o_p4h_sg,
		output wire         o_rg,
		output wire         o_cdsclk1,
		output wire         o_cdsclk2,

		// ADC 数据
		input  wire [7:0]   i_adc_data,

		// FX2 Slave FIFO
		input  wire         i_rd_clk,
		input  wire         i_rd_clk_n,
		input  wire         i_slave_fifo_empty_n,
		input  wire         i_slave_fifo_full_n,
		output wire [15:0]  o_slave_fifo_data,
		output wire         o_slave_fifo_data_wr_en_n,
		output wire         o_slave_fifo_data_last_n,
		output wire         o_slave_fifo_clk,

		// MIG / DDR3
		input  wire         i_ui_clk,
		input  wire         i_mmcm_locked,
		input  wire         i_init_calib_complete,

		// AXI4 Master → MIG S_AXI
		output wire [3:0]   M_AXI_AWID,
		output wire [29:0]  M_AXI_AWADDR,
		output wire [7:0]   M_AXI_AWLEN,
		output wire [2:0]   M_AXI_AWSIZE,
		output wire [1:0]   M_AXI_AWBURST,
		output wire         M_AXI_AWLOCK,
		output wire [3:0]   M_AXI_AWCACHE,
		output wire [2:0]   M_AXI_AWPROT,
		output wire [3:0]   M_AXI_AWQOS,
		output wire [3:0]   M_AXI_AWREGION,
		output wire         M_AXI_AWVALID,
		input  wire         M_AXI_AWREADY,
		output wire [127:0] M_AXI_WDATA,
		output wire [15:0]  M_AXI_WSTRB,
		output wire         M_AXI_WLAST,
		output wire         M_AXI_WVALID,
		input  wire         M_AXI_WREADY,
		input  wire [3:0]   M_AXI_BID,
		input  wire [1:0]   M_AXI_BRESP,
		input  wire         M_AXI_BVALID,
		output wire         M_AXI_BREADY,
		output wire [3:0]   M_AXI_ARID,
		output wire [29:0]  M_AXI_ARADDR,
		output wire [7:0]   M_AXI_ARLEN,
		output wire [2:0]   M_AXI_ARSIZE,
		output wire [1:0]   M_AXI_ARBURST,
		output wire         M_AXI_ARLOCK,
		output wire [3:0]   M_AXI_ARCACHE,
		output wire [2:0]   M_AXI_ARPROT,
		output wire [3:0]   M_AXI_ARQOS,
		output wire [3:0]   M_AXI_ARREGION,
		output wire         M_AXI_ARVALID,
		input  wire         M_AXI_ARREADY,
		input  wire [3:0]   M_AXI_RID,
		input  wire [127:0] M_AXI_RDATA,
		input  wire [1:0]   M_AXI_RRESP,
		input  wire         M_AXI_RLAST,
		input  wire         M_AXI_RVALID,
		output wire         M_AXI_RREADY,
		// User ports ends
		// Do not modify the ports beyond this line

		// Global Clock Signal
		input wire  S_AXI_ACLK,
		// Global Reset Signal. This Signal is Active LOW
		input wire  S_AXI_ARESETN,
		// Write address (issued by master, acceped by Slave)
		input wire [C_S_AXI_ADDR_WIDTH-1 : 0] S_AXI_AWADDR,
		// Write channel Protection type. This signal indicates the
    		// privilege and security level of the transaction, and whether
    		// the transaction is a data access or an instruction access.
		input wire [2 : 0] S_AXI_AWPROT,
		// Write address valid. This signal indicates that the master signaling
    		// valid write address and control information.
		input wire  S_AXI_AWVALID,
		// Write address ready. This signal indicates that the slave is ready
    		// to accept an address and associated control signals.
		output wire  S_AXI_AWREADY,
		// Write data (issued by master, acceped by Slave) 
		input wire [C_S_AXI_DATA_WIDTH-1 : 0] S_AXI_WDATA,
		// Write strobes. This signal indicates which byte lanes hold
    		// valid data. There is one write strobe bit for each eight
    		// bits of the write data bus.    
		input wire [(C_S_AXI_DATA_WIDTH/8)-1 : 0] S_AXI_WSTRB,
		// Write valid. This signal indicates that valid write
    		// data and strobes are available.
		input wire  S_AXI_WVALID,
		// Write ready. This signal indicates that the slave
    		// can accept the write data.
		output wire  S_AXI_WREADY,
		// Write response. This signal indicates the status
    		// of the write transaction.
		output wire [1 : 0] S_AXI_BRESP,
		// Write response valid. This signal indicates that the channel
    		// is signaling a valid write response.
		output wire  S_AXI_BVALID,
		// Response ready. This signal indicates that the master
    		// can accept a write response.
		input wire  S_AXI_BREADY,
		// Read address (issued by master, acceped by Slave)
		input wire [C_S_AXI_ADDR_WIDTH-1 : 0] S_AXI_ARADDR,
		// Protection type. This signal indicates the privilege
    		// and security level of the transaction, and whether the
    		// transaction is a data access or an instruction access.
		input wire [2 : 0] S_AXI_ARPROT,
		// Read address valid. This signal indicates that the channel
    		// is signaling valid read address and control information.
		input wire  S_AXI_ARVALID,
		// Read address ready. This signal indicates that the slave is
    		// ready to accept an address and associated control signals.
		output wire  S_AXI_ARREADY,
		// Read data (issued by slave)
		output wire [C_S_AXI_DATA_WIDTH-1 : 0] S_AXI_RDATA,
		// Read response. This signal indicates the status of the
    		// read transfer.
		output wire [1 : 0] S_AXI_RRESP,
		// Read valid. This signal indicates that the channel is
    		// signaling the required read data.
		output wire  S_AXI_RVALID,
		// Read ready. This signal indicates that the master can
    		// accept the read data and response information.
		input wire  S_AXI_RREADY
	);

	// AXI4LITE signals
	reg [C_S_AXI_ADDR_WIDTH-1 : 0] 	axi_awaddr;
	reg  	axi_awready;
	reg  	axi_wready;
	reg [1 : 0] 	axi_bresp;
	reg  	axi_bvalid;
	reg [C_S_AXI_ADDR_WIDTH-1 : 0] 	axi_araddr;
	reg  	axi_arready;
	reg [C_S_AXI_DATA_WIDTH-1 : 0] 	axi_rdata;
	reg [1 : 0] 	axi_rresp;
	reg  	axi_rvalid;

	// Example-specific design signals
	// local parameter for addressing 32 bit / 64 bit C_S_AXI_DATA_WIDTH
	// ADDR_LSB is used for addressing 32/64 bit registers/memories
	// ADDR_LSB = 2 for 32 bits (n downto 2)
	// ADDR_LSB = 3 for 64 bits (n downto 3)
	localparam integer ADDR_LSB = (C_S_AXI_DATA_WIDTH/32) + 1;
	localparam integer OPT_MEM_ADDR_BITS = 3;
	//----------------------------------------------
	//-- Signals for user logic register space example
	//------------------------------------------------
	//-- Number of Slave Registers 9
	reg [C_S_AXI_DATA_WIDTH-1:0]	slv_reg0;
	reg [C_S_AXI_DATA_WIDTH-1:0]	slv_reg1;
	reg [C_S_AXI_DATA_WIDTH-1:0]	slv_reg2;
	reg [C_S_AXI_DATA_WIDTH-1:0]	slv_reg3;
	reg [C_S_AXI_DATA_WIDTH-1:0]	slv_reg4;
	reg [C_S_AXI_DATA_WIDTH-1:0]	slv_reg5;
	reg [C_S_AXI_DATA_WIDTH-1:0]	slv_reg6;
	reg [C_S_AXI_DATA_WIDTH-1:0]	slv_reg8;
	wire	 slv_reg_rden;
	wire	 slv_reg_wren;
	reg [C_S_AXI_DATA_WIDTH-1:0]	 reg_data_out;
	integer	 byte_index;
	reg	 aw_en;

	//--------------------------------------------------------------
	// 用户逻辑信号
	//--------------------------------------------------------------
	// 中断锁存
	reg         exception_pending_latch;
	reg         tx_done_pending_latch;
	reg         frame_written_pending_latch;  // 帧写入完成锁存 (INTR_STS[10])
	reg  [6:0]  exception_count;           // 帧异常计数, 映射到 STATUS[15:9]

	// 帧发送触发脉冲 (展宽至约 16 个 AXI 周期, 确保 rd_clk 域可靠采样)
	reg         tx_frame_start_reg;
	reg  [3:0]  trigger_stretch_cnt;

	// ccd_ddr 内部连线 (来自 rd_clk / ui_clk 域, 需 CDC 同步)
	wire        ccd_tx_last_n;
	wire        ccd_frame_exception;
	wire        ccd_frame_written;             // 帧完整写入 DDR 脉冲 (rd_clk 域)
	wire [$clog2(MAX_FRAMES+1)-1:0] ccd_frame_num_raw;
	wire [31:0]                      ccd_frame_num;    // 定宽 32bit, 独立 FRAME_NUM 寄存器

	assign ccd_frame_num = ccd_frame_num_raw;  // 自动零扩展, 32bit 定宽

	// FX2 Slave FIFO 最后一字标志: 直接透传 ccd_ddr 的 o_tx_last_n (rd_clk 域)
	assign o_slave_fifo_data_last_n = ccd_tx_last_n;

	// DDR3 初始化完成 (mmcm_locked && init_calib_complete, 来自 ui_clk 域)
	wire ddr3_init_done = i_mmcm_locked && i_init_calib_complete;

	// CDC 2-FF 同步器 (跨时钟域 → S_AXI_ACLK)
	reg  ddr3_init_done_s1,    ddr3_init_done_s2;
	reg  ccd_frame_exception_s1, ccd_frame_exception_s2;
	reg  ccd_tx_last_n_s1,     ccd_tx_last_n_s2;
	reg  ccd_frame_written_s1, ccd_frame_written_s2;


	// STATUS 寄存器组装 (使用同步后信号)
	// 注: 帧计数已移入独立 FRAME_NUM 寄存器 (0x1C), STATUS[7:0] 置 0
	wire [31:0] status_reg;
	assign status_reg = {23'b0,
	                     ddr3_init_done_s2,         // [16]  已同步
	                     exception_count,          // [15:9] 帧异常计数
	                     ccd_frame_exception_s2,    // [8]   已同步
	                     8'b0};                     // [7:0] 空闲

	// FRAME_NUM 寄存器 (0x1C, 只读实时值, 32bit)
	//   frame_num 来自 rd_clk 域 (frames_in_fifo), 未做跨域同步
	//   (与改动前 STATUS[7:0] 一致; 数值每帧变化一次, 撕裂读概率极低且自愈)
	wire [31:0] frame_num_reg;
	assign frame_num_reg = ccd_frame_num;

	// INTR_STS 寄存器 (锁存值) — bit[10]=frame_written_pending, bit[9]=tx_done_pending, bit[8]=exception_pending
	wire [31:0] intr_sts_reg;
	assign intr_sts_reg = {21'b0, frame_written_pending_latch,
	                       tx_done_pending_latch,
	                       exception_pending_latch, 8'b0};

	// I/O Connections assignments

	assign S_AXI_AWREADY	= axi_awready;
	assign S_AXI_WREADY	= axi_wready;
	assign S_AXI_BRESP	= axi_bresp;
	assign S_AXI_BVALID	= axi_bvalid;
	assign S_AXI_ARREADY	= axi_arready;
	assign S_AXI_RDATA	= axi_rdata;
	assign S_AXI_RRESP	= axi_rresp;
	assign S_AXI_RVALID	= axi_rvalid;
	// Implement axi_awready generation
	// axi_awready is asserted for one S_AXI_ACLK clock cycle when both
	// S_AXI_AWVALID and S_AXI_WVALID are asserted. axi_awready is
	// de-asserted when reset is low.

	always @( posedge S_AXI_ACLK )
	begin
	  if ( S_AXI_ARESETN == 1'b0 )
	    begin
	      axi_awready <= 1'b0;
	      aw_en <= 1'b1;
	    end 
	  else
	    begin    
	      if (~axi_awready && S_AXI_AWVALID && S_AXI_WVALID && aw_en)
	        begin
	          // slave is ready to accept write address when 
	          // there is a valid write address and write data
	          // on the write address and data bus. This design 
	          // expects no outstanding transactions. 
	          axi_awready <= 1'b1;
	          aw_en <= 1'b0;
	        end
	        else if (S_AXI_BREADY && axi_bvalid)
	            begin
	              aw_en <= 1'b1;
	              axi_awready <= 1'b0;
	            end
	      else           
	        begin
	          axi_awready <= 1'b0;
	        end
	    end 
	end       

	// Implement axi_awaddr latching
	// This process is used to latch the address when both 
	// S_AXI_AWVALID and S_AXI_WVALID are valid. 

	always @( posedge S_AXI_ACLK )
	begin
	  if ( S_AXI_ARESETN == 1'b0 )
	    begin
	      axi_awaddr <= 0;
	    end 
	  else
	    begin    
	      if (~axi_awready && S_AXI_AWVALID && S_AXI_WVALID && aw_en)
	        begin
	          // Write Address latching 
	          axi_awaddr <= S_AXI_AWADDR;
	        end
	    end 
	end       

	// Implement axi_wready generation
	// axi_wready is asserted for one S_AXI_ACLK clock cycle when both
	// S_AXI_AWVALID and S_AXI_WVALID are asserted. axi_wready is 
	// de-asserted when reset is low. 

	always @( posedge S_AXI_ACLK )
	begin
	  if ( S_AXI_ARESETN == 1'b0 )
	    begin
	      axi_wready <= 1'b0;
	    end 
	  else
	    begin    
	      if (~axi_wready && S_AXI_WVALID && S_AXI_AWVALID && aw_en )
	        begin
	          // slave is ready to accept write data when 
	          // there is a valid write address and write data
	          // on the write address and data bus. This design 
	          // expects no outstanding transactions. 
	          axi_wready <= 1'b1;
	        end
	      else
	        begin
	          axi_wready <= 1'b0;
	        end
	    end 
	end       

	// Implement memory mapped register select and write logic generation
	// The write data is accepted and written to memory mapped registers when
	// axi_awready, S_AXI_WVALID, axi_wready and S_AXI_WVALID are asserted. Write strobes are used to
	// select byte enables of slave registers while writing.
	// These registers are cleared when reset (active low) is applied.
	// Slave register write enable is asserted when valid address and data are available
	// and the slave is ready to accept the write address and write data.
	assign slv_reg_wren = axi_wready && S_AXI_WVALID && axi_awready && S_AXI_AWVALID;

	always @( posedge S_AXI_ACLK )
	begin
	  if ( S_AXI_ARESETN == 1'b0 )
	    begin
	      slv_reg0 <= 0;
	      slv_reg1 <= 0;
	      slv_reg2 <= 0;
	      slv_reg4 <= 0;
	      slv_reg8 <= 0;
	      trigger_stretch_cnt <= 4'd0;
	    end 
	  else begin
	    // 展宽计数器自动递减 (与触发写共用同一 always 块, 避免多驱动)
	    if (trigger_stretch_cnt != 0)
	        trigger_stretch_cnt <= trigger_stretch_cnt - 1'b1;

	    if (slv_reg_wren)
	      begin
	        case ( axi_awaddr[ADDR_LSB+OPT_MEM_ADDR_BITS:ADDR_LSB] )
	          // 0x00 — CTRL
	          4'h0:
	            for ( byte_index = 0; byte_index <= (C_S_AXI_DATA_WIDTH/8)-1; byte_index = byte_index+1 )
	              if ( S_AXI_WSTRB[byte_index] == 1 ) begin
	                slv_reg0[(byte_index*8) +: 8] <= S_AXI_WDATA[(byte_index*8) +: 8];
	              end  
	          // 0x04 — IMG_SIZE
	          4'h1:
	            for ( byte_index = 0; byte_index <= (C_S_AXI_DATA_WIDTH/8)-1; byte_index = byte_index+1 )
	              if ( S_AXI_WSTRB[byte_index] == 1 ) begin
	                slv_reg1[(byte_index*8) +: 8] <= S_AXI_WDATA[(byte_index*8) +: 8];
	              end  
	          // 0x08 — BEVEL_BLANK
	          4'h2:
	            for ( byte_index = 0; byte_index <= (C_S_AXI_DATA_WIDTH/8)-1; byte_index = byte_index+1 )
	              if ( S_AXI_WSTRB[byte_index] == 1 ) begin
	                slv_reg2[(byte_index*8) +: 8] <= S_AXI_WDATA[(byte_index*8) +: 8];
	              end  
	          // 0x0C — TRIGGER (写 1 启动展宽计数器, 16 周期 ≈ 160ns @100MHz)
	          4'h3:
	            if (S_AXI_WDATA[0] && S_AXI_WSTRB[0] && trigger_stretch_cnt == 0)
	              trigger_stretch_cnt <= 4'd15;
	          // 0x10 — STATUS (只读, 写忽略)
	          4'h4: ;
	          // 0x14 — INTR_EN
	          4'h5:
	            for ( byte_index = 0; byte_index <= (C_S_AXI_DATA_WIDTH/8)-1; byte_index = byte_index+1 )
	              if ( S_AXI_WSTRB[byte_index] == 1 ) begin
	                slv_reg4[(byte_index*8) +: 8] <= S_AXI_WDATA[(byte_index*8) +: 8];
	              end  
	          // 0x18 — INTR_STS (写 1 清除, 由中断锁存块处理)
	          4'h6: ;
	          // 0x1C — FRAME_NUM (只读, 写忽略)
	          4'h7: ;
	          // 0x20 — 保留
	          4'h8:
	            for ( byte_index = 0; byte_index <= (C_S_AXI_DATA_WIDTH/8)-1; byte_index = byte_index+1 )
	              if ( S_AXI_WSTRB[byte_index] == 1 ) begin
	                slv_reg8[(byte_index*8) +: 8] <= S_AXI_WDATA[(byte_index*8) +: 8];
	              end  
	          default : ;
	        endcase
	      end
	  end
	end    

	// Implement write response logic generation
	// The write response and response valid signals are asserted by the slave 
	// when axi_wready, S_AXI_WVALID, axi_wready and S_AXI_WVALID are asserted.  
	// This marks the acceptance of address and indicates the status of 
	// write transaction.

	always @( posedge S_AXI_ACLK )
	begin
	  if ( S_AXI_ARESETN == 1'b0 )
	    begin
	      axi_bvalid  <= 0;
	      axi_bresp   <= 2'b0;
	    end 
	  else
	    begin    
	      if (axi_awready && S_AXI_AWVALID && ~axi_bvalid && axi_wready && S_AXI_WVALID)
	        begin
	          // indicates a valid write response is available
	          axi_bvalid <= 1'b1;
	          axi_bresp  <= 2'b0; // 'OKAY' response 
	        end                   // work error responses in future
	      else
	        begin
	          if (S_AXI_BREADY && axi_bvalid) 
	            //check if bready is asserted while bvalid is high) 
	            //(there is a possibility that bready is always asserted high)   
	            begin
	              axi_bvalid <= 1'b0; 
	            end  
	        end
	    end
	end   

	// Implement axi_arready generation
	// axi_arready is asserted for one S_AXI_ACLK clock cycle when
	// S_AXI_ARVALID is asserted. axi_awready is 
	// de-asserted when reset (active low) is asserted. 
	// The read address is also latched when S_AXI_ARVALID is 
	// asserted. axi_araddr is reset to zero on reset assertion.

	always @( posedge S_AXI_ACLK )
	begin
	  if ( S_AXI_ARESETN == 1'b0 )
	    begin
	      axi_arready <= 1'b0;
	      axi_araddr  <= 32'b0;
	    end 
	  else
	    begin    
	      if (~axi_arready && S_AXI_ARVALID)
	        begin
	          // indicates that the slave has acceped the valid read address
	          axi_arready <= 1'b1;
	          // Read address latching
	          axi_araddr  <= S_AXI_ARADDR;
	        end
	      else
	        begin
	          axi_arready <= 1'b0;
	        end
	    end 
	end       

	// Implement axi_arvalid generation
	// axi_rvalid is asserted for one S_AXI_ACLK clock cycle when both 
	// S_AXI_ARVALID and axi_arready are asserted. The slave registers 
	// data are available on the axi_rdata bus at this instance. The 
	// assertion of axi_rvalid marks the validity of read data on the 
	// bus and axi_rresp indicates the status of read transaction.axi_rvalid 
	// is deasserted on reset (active low). axi_rresp and axi_rdata are 
	// cleared to zero on reset (active low).  
	always @( posedge S_AXI_ACLK )
	begin
	  if ( S_AXI_ARESETN == 1'b0 )
	    begin
	      axi_rvalid <= 0;
	      axi_rresp  <= 0;
	    end 
	  else
	    begin    
	      if (axi_arready && S_AXI_ARVALID && ~axi_rvalid)
	        begin
	          // Valid read data is available at the read data bus
	          axi_rvalid <= 1'b1;
	          axi_rresp  <= 2'b0; // 'OKAY' response
	        end   
	      else if (axi_rvalid && S_AXI_RREADY)
	        begin
	          // Read data is accepted by the master
	          axi_rvalid <= 1'b0;
	        end                
	    end
	end    

	// Implement memory mapped register select and read logic generation
	// Slave register read enable is asserted when valid address is available
	// and the slave is ready to accept the read address.
	assign slv_reg_rden = axi_arready & S_AXI_ARVALID & ~axi_rvalid;
	always @(*)
	begin
	      // Address decoding for reading registers
	      case ( axi_araddr[ADDR_LSB+OPT_MEM_ADDR_BITS:ADDR_LSB] )
	        4'h0   : reg_data_out <= slv_reg0;      // CTRL
	        4'h1   : reg_data_out <= slv_reg1;      // IMG_SIZE
	        4'h2   : reg_data_out <= slv_reg2;      // BEVEL_BLANK
	        4'h3   : reg_data_out <= 32'h0;         // TRIGGER (只写)
	        4'h4   : reg_data_out <= status_reg;    // STATUS (实时)
	        4'h5   : reg_data_out <= slv_reg4;      // INTR_EN
	        4'h6   : reg_data_out <= intr_sts_reg;  // INTR_STS (锁存值)
	        4'h7   : reg_data_out <= frame_num_reg; // FRAME_NUM (实时)
	        4'h8   : reg_data_out <= slv_reg8;      // 保留
	        default : reg_data_out <= 0;
	      endcase
	end

	// Output register or memory read data
	always @( posedge S_AXI_ACLK )
	begin
	  if ( S_AXI_ARESETN == 1'b0 )
	    begin
	      axi_rdata  <= 0;
	    end 
	  else
	    begin    
	      // When there is a valid read address (S_AXI_ARVALID) with 
	      // acceptance of read address by the slave (axi_arready), 
	      // output the read dada 
	      if (slv_reg_rden)
	        begin
	          axi_rdata <= reg_data_out;     // register read data
	        end   
	    end
	end    

	// ==================================================================
	// 用户逻辑: ccd_ddr 例化 + 中断 + 触发脉冲
	// ==================================================================

	// ---- 触发脉冲生成 (寄存器输出, 展宽 16 周期 → rd_clk 域可靠采样) ----
	// trigger_stretch_cnt 仅在寄存器写块中驱动 (单一 always 块, 无多驱动)
	always @(posedge S_AXI_ACLK or negedge S_AXI_ARESETN) begin
	    if (!S_AXI_ARESETN) begin
	        tx_frame_start_reg <= 1'b0;
	    end else begin
	        tx_frame_start_reg <= (trigger_stretch_cnt != 0);
	    end
	end

	// ---- CDC 2-FF 同步器 (ddr3_done: MIG域→AXI, exception: ui_clk域→AXI,
	//      tx_last_n / frame_written: rd_clk域→AXI) ----
	always @(posedge S_AXI_ACLK or negedge S_AXI_ARESETN) begin
	    if (!S_AXI_ARESETN) begin
	        ddr3_init_done_s1    <= 1'b0;
	        ddr3_init_done_s2    <= 1'b0;
	        ccd_frame_exception_s1 <= 1'b0;
	        ccd_frame_exception_s2 <= 1'b0;
	        ccd_tx_last_n_s1     <= 1'b1;
	        ccd_tx_last_n_s2     <= 1'b1;
	        ccd_frame_written_s1 <= 1'b0;
	        ccd_frame_written_s2 <= 1'b0;
	    end else begin
	        ddr3_init_done_s1    <= ddr3_init_done;
	        ddr3_init_done_s2    <= ddr3_init_done_s1;
	        ccd_frame_exception_s1 <= ccd_frame_exception;
	        ccd_frame_exception_s2 <= ccd_frame_exception_s1;
	        ccd_tx_last_n_s1     <= ccd_tx_last_n;
	        ccd_tx_last_n_s2     <= ccd_tx_last_n_s1;
	        ccd_frame_written_s1 <= ccd_frame_written;
	        ccd_frame_written_s2 <= ccd_frame_written_s1;
	    end
	end

	// ---- 中断边沿检测 (基于同步后信号) ----
	reg ccd_frame_exception_s2_d;
	wire ccd_frame_exception_rise;
	reg ccd_tx_last_n_s2_d;
	wire ccd_tx_done_fall;
	reg ccd_frame_written_s2_d;
	wire ccd_frame_written_rise;

	always @(posedge S_AXI_ACLK or negedge S_AXI_ARESETN) begin
	    if (!S_AXI_ARESETN) begin
	        ccd_frame_exception_s2_d <= 1'b0;
	        ccd_tx_last_n_s2_d   <= 1'b1;
	        ccd_frame_written_s2_d <= 1'b0;
	    end else begin
	        ccd_frame_exception_s2_d <= ccd_frame_exception_s2;
	        ccd_tx_last_n_s2_d   <= ccd_tx_last_n_s2;
	        ccd_frame_written_s2_d <= ccd_frame_written_s2;
	    end
	end

	assign ccd_frame_exception_rise = ccd_frame_exception_s2 && !ccd_frame_exception_s2_d;
	assign ccd_tx_done_fall         = !ccd_tx_last_n_s2 && ccd_tx_last_n_s2_d;
	assign ccd_frame_written_rise   = ccd_frame_written_s2 && !ccd_frame_written_s2_d;

	// ---- 中断锁存与写 1 清除 ----
	always @(posedge S_AXI_ACLK or negedge S_AXI_ARESETN) begin
	    if (!S_AXI_ARESETN) begin
	        exception_pending_latch <= 1'b0;
	        tx_done_pending_latch <= 1'b0;
	        frame_written_pending_latch <= 1'b0;
	        exception_count        <= 7'd0;
	    end else begin
	        // 帧异常计数 (饱和, 不绕回)
	        if (ccd_frame_exception_rise && exception_count != 7'd127)
	            exception_count <= exception_count + 1'b1;
	        // Exception: 上升沿置位, CPU 写 INTR_STS[8]=1 清除
	        if (ccd_frame_exception_rise)
	            exception_pending_latch <= 1'b1;
	        else if (slv_reg_wren &&
	                 (axi_awaddr[ADDR_LSB+OPT_MEM_ADDR_BITS:ADDR_LSB] == 4'h6) &&
	                 S_AXI_WDATA[8])
	            exception_pending_latch <= 1'b0;
	        // TX done: o_tx_last_n 下降沿置位, CPU 写 INTR_STS[9]=1 清除
	        if (ccd_tx_done_fall)
	            tx_done_pending_latch <= 1'b1;
	        else if (slv_reg_wren &&
	                 (axi_awaddr[ADDR_LSB+OPT_MEM_ADDR_BITS:ADDR_LSB] == 4'h6) &&
	                 S_AXI_WDATA[9])
	            tx_done_pending_latch <= 1'b0;
	        // 帧写入完成: 上升沿置位, CPU 写 INTR_STS[10]=1 清除
	        if (ccd_frame_written_rise)
	            frame_written_pending_latch <= 1'b1;
	        else if (slv_reg_wren &&
	                 (axi_awaddr[ADDR_LSB+OPT_MEM_ADDR_BITS:ADDR_LSB] == 4'h6) &&
	                 S_AXI_WDATA[10])
	            frame_written_pending_latch <= 1'b0;
	    end
	end

	// ---- 中断输出 ----
	assign intr = (exception_pending_latch && slv_reg4[8])
	           || (tx_done_pending_latch && slv_reg4[9])
	           || (frame_written_pending_latch && slv_reg4[10]);

	// ---- ccd_ddr 例化 ----
	ccd_ddr #(
	    .MAX_FRAME_DEPTH(MAX_FRAME_DEPTH),
	    .MAX_FRAMES     (MAX_FRAMES)
	) u_ccd_ddr (
	    .i_ccd_clk      (S_AXI_ACLK),
	    .i_rst_n        (S_AXI_ARESETN), 
	    .i_exposure     (slv_reg0[0]),
	    .i_freq_sel     (slv_reg0[1]),
	    .i_cdsclk_delay (slv_reg0[11:5]),
	    .i_image_width  (slv_reg1[15:0]),
	    .i_image_height (slv_reg1[31:16]),
	    .i_bevel_left   (slv_reg2[3:0]),
	    .i_bevel_top    (slv_reg2[7:4]),
	    .i_bevel_right  (slv_reg2[11:8]),
	    .i_bevel_bottom (slv_reg2[15:12]),
	    .i_blank_left   (slv_reg2[19:16]),
	    .i_blank_right  (slv_reg2[23:20]),
	    .i_read_mode    (slv_reg0[4:3]),
	    .i_mock_mode    (slv_reg0[2]),
	    .i_adc_data     (i_adc_data),
	    .o_adcclk       (o_adcclk),
	    .o_p1v          (o_p1v),
	    .o_p2v_tg       (o_p2v_tg),
	    .o_p1h          (o_p1h),
	    .o_p2h          (o_p2h),
	    .o_p3h          (o_p3h),
	    .o_p4h_sg       (o_p4h_sg),
	    .o_rg           (o_rg),
	    .o_cdsclk1      (o_cdsclk1),
	    .o_cdsclk2      (o_cdsclk2),
	    .i_rd_clk       (i_rd_clk),
	    .i_rd_clk_n     (i_rd_clk_n),
	    .o_slave_fifo_clk(o_slave_fifo_clk),
	    .i_tx_frame_start(tx_frame_start_reg),
	    .i_slave_fifo_empty_n(i_slave_fifo_empty_n),
	    .i_slave_fifo_full_n (i_slave_fifo_full_n),
	    .o_slave_fifo_data    (o_slave_fifo_data),
	    .o_slave_fifo_data_valid_n(o_slave_fifo_data_wr_en_n),
	    .o_tx_last_n (ccd_tx_last_n),
	    .o_frame_num    (ccd_frame_num_raw),
	    .o_frame_written (ccd_frame_written),
	    .o_frame_exception(ccd_frame_exception),
	    .i_ui_clk       (i_ui_clk),
	    .i_mmcm_locked    (i_mmcm_locked),
	    .i_init_calib_complete(i_init_calib_complete),
	    .M_AXI_AWID     (M_AXI_AWID),
	    .M_AXI_AWADDR   (M_AXI_AWADDR),
	    .M_AXI_AWLEN    (M_AXI_AWLEN),
	    .M_AXI_AWSIZE   (M_AXI_AWSIZE),
	    .M_AXI_AWBURST  (M_AXI_AWBURST),
	    .M_AXI_AWLOCK   (M_AXI_AWLOCK),
	    .M_AXI_AWCACHE  (M_AXI_AWCACHE),
	    .M_AXI_AWPROT   (M_AXI_AWPROT),
	    .M_AXI_AWQOS    (M_AXI_AWQOS),
	    .M_AXI_AWREGION (M_AXI_AWREGION),
	    .M_AXI_AWVALID  (M_AXI_AWVALID),
	    .M_AXI_AWREADY  (M_AXI_AWREADY),
	    .M_AXI_WDATA    (M_AXI_WDATA),
	    .M_AXI_WSTRB    (M_AXI_WSTRB),
	    .M_AXI_WLAST    (M_AXI_WLAST),
	    .M_AXI_WVALID   (M_AXI_WVALID),
	    .M_AXI_WREADY   (M_AXI_WREADY),
	    .M_AXI_BID      (M_AXI_BID),
	    .M_AXI_BRESP    (M_AXI_BRESP),
	    .M_AXI_BVALID   (M_AXI_BVALID),
	    .M_AXI_BREADY   (M_AXI_BREADY),
	    .M_AXI_ARID     (M_AXI_ARID),
	    .M_AXI_ARADDR   (M_AXI_ARADDR),
	    .M_AXI_ARLEN    (M_AXI_ARLEN),
	    .M_AXI_ARSIZE   (M_AXI_ARSIZE),
	    .M_AXI_ARBURST  (M_AXI_ARBURST),
	    .M_AXI_ARLOCK   (M_AXI_ARLOCK),
	    .M_AXI_ARCACHE  (M_AXI_ARCACHE),
	    .M_AXI_ARPROT   (M_AXI_ARPROT),
	    .M_AXI_ARQOS    (M_AXI_ARQOS),
	    .M_AXI_ARREGION (M_AXI_ARREGION),
	    .M_AXI_ARVALID  (M_AXI_ARVALID),
	    .M_AXI_ARREADY  (M_AXI_ARREADY),
	    .M_AXI_RID      (M_AXI_RID),
	    .M_AXI_RDATA    (M_AXI_RDATA),
	    .M_AXI_RRESP    (M_AXI_RRESP),
	    .M_AXI_RLAST    (M_AXI_RLAST),
	    .M_AXI_RVALID   (M_AXI_RVALID),
	    .M_AXI_RREADY   (M_AXI_RREADY)
	);

	// User logic ends

	endmodule

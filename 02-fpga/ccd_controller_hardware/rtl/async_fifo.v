`timescale 1ns / 1ps
//==============================================================================
// Module : async_fifo
// Desc   : 通用异步 FIFO, 支持任意 DATA_WIDTH 和 FIFO_DEPTH。
//          使用双端口 BRAM + 格雷码指针跨时钟域同步。
//          深度必须为 2 的幂。
//==============================================================================
module async_fifo #(
    parameter DATA_WIDTH = 16,
    parameter FIFO_DEPTH = 1024
) (
    input  wire             i_wr_clk,
    input  wire             i_rst_n,          // 异步复位, 低有效 (同时复位读写两侧)

    input  wire [DATA_WIDTH-1:0] i_wr_data,
    input  wire             i_wr_en,
    output wire             o_full,
    output wire             o_almost_full,

    input  wire             i_rd_clk,
    output wire [DATA_WIDTH-1:0] o_rd_data,
    input  wire             i_rd_en,
    output wire             o_empty,
    output wire             o_almost_empty,
    output wire             o_valid
);

    localparam ADDR_WIDTH = $clog2(FIFO_DEPTH);

    // 存储体
    reg [DATA_WIDTH-1:0] mem [0:FIFO_DEPTH-1];

    // 指针 (二进制)
    reg [ADDR_WIDTH:0] wr_ptr;      // 含 MSB 用于满/空判断
    reg [ADDR_WIDTH:0] rd_ptr;

    // 格雷码指针
    reg [ADDR_WIDTH:0] wr_gray;
    reg [ADDR_WIDTH:0] rd_gray;

    // 同步后的指针
    reg [ADDR_WIDTH:0] wr_gray_sync [1:0];  // 写→读
    reg [ADDR_WIDTH:0] rd_gray_sync [1:0];  // 读→写

    wire [ADDR_WIDTH-1:0] wr_addr = wr_ptr[ADDR_WIDTH-1:0];
    wire [ADDR_WIDTH-1:0] rd_addr = rd_ptr[ADDR_WIDTH-1:0];

    // 格雷码转换
    function [ADDR_WIDTH:0] bin2gray;
        input [ADDR_WIDTH:0] bin;
        bin2gray = bin ^ (bin >> 1);
    endfunction

    // 写指针
    always @(posedge i_wr_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            wr_ptr  <= 0;
            wr_gray <= 0;
        end else if (i_wr_en && !o_full) begin
            wr_ptr  <= wr_ptr + 1'b1;
            wr_gray <= bin2gray(wr_ptr + 1'b1);
        end
    end

    // 写数据
    always @(posedge i_wr_clk) begin
        if (i_wr_en && !o_full)
            mem[wr_addr] <= i_wr_data;
    end

    // ====================================================================
    // 读时钟域 — 上升沿: 采样输入 i_rd_en, 更新指针/格雷码, 同步写格雷码
    // ====================================================================

    // 读指针 (上升沿采样 i_rd_en)
    always @(posedge i_rd_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            rd_ptr  <= 0;
            rd_gray <= 0;
        end else if (i_rd_en && !o_empty) begin
            rd_ptr  <= rd_ptr + 1'b1;
            rd_gray <= bin2gray(rd_ptr + 1'b1);
        end
    end

    // almost_empty: 在上升沿用读出前的 rd_ptr 预判,
    //               在下降沿注册输出 (与 o_rd_data / o_empty 同步)
    reg almost_empty_int;   // 上升沿预判值
    reg almost_empty_reg;   // 下降沿输出寄存器

    always @(posedge i_rd_clk) begin
        almost_empty_int <= (bin2gray(rd_ptr + 1'b1) == wr_gray_synced);
    end

    always @(negedge i_rd_clk or negedge i_rst_n) begin
        if (!i_rst_n)
            almost_empty_reg <= 1'b0;
        else
            almost_empty_reg <= almost_empty_int;
    end
    assign o_almost_empty = almost_empty_reg;

    // 读数据 (上升沿从 BRAM 读取, 此时 rd_addr 仍为 NBA 前的旧值)
    reg [DATA_WIDTH-1:0] rd_data_int;
    always @(posedge i_rd_clk) begin
        if (i_rd_en && !o_empty)
            rd_data_int <= mem[rd_addr];
    end

    // 同步格雷码: 写格雷码 → 读时钟域 (上升沿)
    always @(posedge i_rd_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            wr_gray_sync[0] <= 0;
            wr_gray_sync[1] <= 0;
        end else begin
            wr_gray_sync[0] <= wr_gray;
            wr_gray_sync[1] <= wr_gray_sync[0];
        end
    end

    // ====================================================================
    // 读时钟域 — 下降沿: 更新输出, 为下游提供半周期建立时间
    // ====================================================================

    // 读数据输出 (下降沿更新)
    reg [DATA_WIDTH-1:0] rd_data_reg;
    always @(negedge i_rd_clk) begin
        rd_data_reg <= rd_data_int;
    end
    assign o_rd_data = rd_data_reg;

    // 空标志 (下降沿更新)
    reg empty_reg;
    wire [ADDR_WIDTH:0] wr_gray_synced = wr_gray_sync[1];
    always @(negedge i_rd_clk or negedge i_rst_n) begin
        if (!i_rst_n)
            empty_reg <= 1'b1;
        else
            empty_reg <= (rd_gray == wr_gray_synced);
    end
    assign o_empty = empty_reg;

    // 读数据有效 (下降沿更新)
    reg valid_reg;
    always @(negedge i_rd_clk or negedge i_rst_n) begin
        if (!i_rst_n)
            valid_reg <= 1'b0;
        else
            valid_reg <= i_rd_en && !empty_reg;
    end
    assign o_valid = valid_reg;

    // 同步格雷码: 读格雷码 → 写时钟域
    always @(posedge i_wr_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            rd_gray_sync[0] <= 0;
            rd_gray_sync[1] <= 0;
        end else begin
            rd_gray_sync[0] <= rd_gray;
            rd_gray_sync[1] <= rd_gray_sync[0];
        end
    end

    // ====================================================================
    // 满/Almost-full 标志 (写时钟域, 上升沿组合)
    // ====================================================================

    // 满标志: 格雷码 MSB 相反, 次高位相反, 其余位相同
    wire [ADDR_WIDTH:0] rd_gray_synced = rd_gray_sync[1];
    assign o_full = (wr_gray[ADDR_WIDTH]   != rd_gray_synced[ADDR_WIDTH]) &&
                    (wr_gray[ADDR_WIDTH-1] != rd_gray_synced[ADDR_WIDTH-1]) &&
                    (wr_gray[ADDR_WIDTH-2:0] == rd_gray_synced[ADDR_WIDTH-2:0]);

    // Almost full: 剩余空间 < FIFO_DEPTH/4
    wire [ADDR_WIDTH:0] space_left = (FIFO_DEPTH - (wr_ptr - rd_gray_synced));
    assign o_almost_full = (space_left < (FIFO_DEPTH >> 2));

endmodule

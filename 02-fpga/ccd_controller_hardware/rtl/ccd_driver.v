`timescale 1ns / 1ps
//==============================================================================
// Module : ccd_driver
// Desc   : CCD 顶层驱动模块。
//          实例化 ccd_phase_gen,产生 4 相 SCLK + 1 相 RG 相位时钟;
//          组合出 ADCCLK / P1V / P2V(TG) / P1H / P2H / P3H / P4H(SG) / RG
//          等 CCD 驱动信号。
//
//          内嵌三态状态机 (IDLE / VERTICAL_SHIFT / HORIZONTAL_SHIFT),
//          所有状态转移与 s_clk (sclk_p0) 上升沿同步。
//          计数目标 v/h/l 由图像尺寸/消隐/空白参数和读出模式
//          在内部计算得出,支持 image / line binning 两种模式。
//          状态转移条件:
//            IDLE → VERTICAL_SHIFT         : exposure 下降沿 (已同步+展宽)
//            VERTICAL_SHIFT → IDLE         : i_exposure = 1 (强制中止)
//            VERTICAL_SHIFT → HORIZONTAL   : v_counter 计满 (一行垂直移位完成)
//            HORIZONTAL_SHIFT → IDLE       : i_exposure = 1 (强制中止)
//            HORIZONTAL → VERTICAL_SHIFT   : h_counter 计满 (一行水平移位完成)
//                                            且未到最后一帧行
//            HORIZONTAL → IDLE             : h_counter 计满 (一行水平移位完成)
//                                            且已到最后一帧行
//==============================================================================
module ccd_driver (
    input  wire         i_clk,           // 系统时钟 (默认 100 MHz)
    input  wire         i_rst_n,         // 异步复位,低有效
    input  wire         i_exposure,      // 曝光信号
    input  wire         i_freq_sel,      // SCLK 频率选择: 0 -> 100kHz, 1 -> 500kHz
    input  wire [6:0]   i_cdsclk_delay,  // CDSCLK 微调延时,单位系统时钟周期 (10ns)
    input  wire [15:0]  i_image_width,   // 图像宽度 (pixels)
    input  wire [15:0]  i_image_height,  // 图像高度 (pixels)
    input  wire [3:0]   i_bevel_left,    // 左侧消隐
    input  wire [3:0]   i_bevel_top,     // 顶部消隐
    input  wire [3:0]   i_bevel_right,   // 右侧消隐
    input  wire [3:0]   i_bevel_bottom,  // 底部消隐
    input  wire [3:0]   i_blank_left,    // 左侧空白
    input  wire [3:0]   i_blank_right,   // 右侧空白
    input  wire [1:0]   i_read_mode,     // 读出模式: 0=line binning, 1=image
    // --- ADC 数据接口 ---
    input  wire [7:0]   i_adc_data,      // ADC 采样数据 (8bit, 在 ADCCLK 上升/下降沿变化)
    // --- CCD 驱动信号 (受 exposure 门控,ADCCLK 除外) ---
    output wire o_adcclk,      // ADCCLK  同相       50% (复位 0)
    output wire o_p1v,         // P1V     落后 270°  50% (复位 0)
    output wire o_p2v_tg,      // P2V(TG) 落后 90°   50% (复位 0)
    output wire o_p1h,         // P1H     落后 180°  50% (复位 1)
    output wire o_p2h,         // P2H     落后 270°  50% (复位 0)
    output wire o_p3h,         // P3H     同相       50% (复位 0)
    output wire o_p4h_sg,      // P4H(SG) 落后 90°   50% (复位 0)
    output wire o_rg,           // RG      落后 90°   25% (复位 1)
    // --- CDS 采样时钟 ---
    output wire o_cdsclk1,       // CDSCLK1 落后 180°  12.5% (复位 0)
    output wire o_cdsclk2,       // CDSCLK2 落后 270°  12.5% (复位 0)
    // --- 像素数据类型指示 (s_clk 上升沿同步) ---
    output wire o_data_valid,    // 高电平表示当前像素有效
    output wire [1:0] o_pixel_type,  // 00=bevel, 01=blank, 10=active
    output wire [15:0] o_pixel_data,  // 16bit 像素数据 (与 o_data_valid/o_pixel_type 对齐)
    // --- 帧边界标记 (ccd_frame_buf 接口) ---
    output wire o_frame_start,   // 帧起始脉冲 (新一帧的第一个有效像素位置)
    output wire o_frame_end ,    // 帧结束脉冲 (一帧中所有像素输出完毕)
    output wire o_frame_idle     // 帧数据串出
);

// 内部线网:phase_gen 的相位输出 (作为后续 CCD 驱动信号的来源)
wire sclk_p0_w;
wire sclk_p90_w;
wire sclk_p180_w;
wire sclk_p270_w;
wire rg_p90_w;
wire rg_p270_w;
wire cdsclk1_w;
wire cdsclk2_w;

// ==================================================================
// 读出参数计算 — 从图像尺寸/消隐/空白算出 v/h/l 计数目标
//   line binning : v = bevel_top + image_height + bevel_bottom
//                   h = blank_left + bevel_left + image_width
//                     + bevel_right + blank_right
//                   l = 1
//   image        : v = 1
//                   h = 同上
//                   l = bevel_top + image_height + bevel_bottom
// ==================================================================
wire [31:0] v_shift_cnt;
wire [31:0] h_shift_cnt;
wire [31:0] line_cnt;
reg [1:0]  exp_sync;
reg        exp_sync_d1;
reg [31:0] exp_stretch_cnt;
wire       exp_fall_stretched;
reg [1:0] state_reg, state_next;
reg       freq_sel_prev;
reg       exp_fall_sync;
reg [31:0] v_counter;
reg [31:0] h_counter;
reg [31:0] l_counter;
wire       freq_changed;
wire       exposure_falling;
wire       vstate;
wire       hstate;
reg        p1v_enable;
reg        p2v_tg_enable;
reg        p1h_enable;
reg        p2h_enable;
reg        p3h_enable;
reg        p4h_sg_enable;
reg        rg_enable;
reg        cdsclk_enable;
reg        data_valid_reg;
reg [1:0]  pixel_type_reg;
wire       outputs_idle;
reg [7:0]  adc_data_rise;
reg [15:0] pixel_data_reg;
reg        frame_start_reg;
reg        frame_end_reg;

assign v_shift_cnt = (i_read_mode == 2'd0) ?
    (i_bevel_top + i_image_height + i_bevel_bottom) :  // line binning
    32'd1;  // image

assign h_shift_cnt = i_blank_left + i_bevel_left + i_image_width +
                     i_bevel_right + i_blank_right;

assign line_cnt = (i_read_mode == 2'd0) ?
    32'd1 :  // line binning
    (i_bevel_top + i_image_height + i_bevel_bottom);  // image

// ------------------------------------------------------------------
// 多相时钟生成 (自由运行,不受 exposure 影响)
// ------------------------------------------------------------------
ccd_phase_gen #(
    .SYS_CLK_FREQ_HZ(100_000_000)
) u_ccd_phase_gen (
    .i_clk        (i_clk),
    .i_rst_n      (i_rst_n),
    .i_freq_sel   (i_freq_sel),
    .o_sclk_p0    (sclk_p0_w),
    .o_sclk_p90   (sclk_p90_w),
    .o_sclk_p180  (sclk_p180_w),
    .o_sclk_p270  (sclk_p270_w),
    .o_rg_p90     (rg_p90_w),
    .o_rg_p270    (rg_p270_w)
);

// ------------------------------------------------------------------
// CDS 采样时钟生成 (自由运行,受使能门控)
// ------------------------------------------------------------------
cdsclk_gen #(
    .SYS_CLK_FREQ_HZ(100_000_000)
) u_cdsclk_gen (
    .i_clk        (i_clk),
    .i_rst_n      (i_rst_n),
    .i_freq_sel   (i_freq_sel),
    .i_delay      (i_cdsclk_delay),
    .o_cdsclk1    (cdsclk1_w),
    .o_cdsclk2    (cdsclk2_w)
);

// --- SCLK / RG 内部线网 (供状态机/输出级使用) ---

// ==================================================================
// exposure 下降沿检测 — i_clk 域同步 + 脉冲展宽
//   i_exposure 是异步信号,先用 100 MHz 系统时钟双级同步,
//   捕捉下降沿(1→0)后展宽至 20 µs,确保慢速 sclk_p0 域可靠采样。
// ==================================================================
always @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        exp_sync       <= 2'b11;
        exp_sync_d1    <= 1'b1;
        exp_stretch_cnt <= 32'd0;
    end else begin
        exp_sync[0] <= i_exposure;
        exp_sync[1] <= exp_sync[0];
        exp_sync_d1 <= exp_sync[1];

        // 下降沿检测: 同步后的值从 1→0
        if (exp_sync_d1 && !exp_sync[1])
            exp_stretch_cnt <= 32'd2000;  // 2000 × 10 ns = 20 µs

        // 展宽计数器递减
        if (exp_stretch_cnt > 0)
            exp_stretch_cnt <= exp_stretch_cnt - 1'b1;
    end
end

// 展宽后的脉冲 (高电平持续 ~20 µs)
assign exp_fall_stretched = (exp_stretch_cnt > 0);

// ==================================================================
// 三态状态机 (以 sclk_p0 为同步时钟)
// ==================================================================
localparam STATE_IDLE            = 2'd0;
localparam STATE_VERTICAL_SHIFT  = 2'd1;
localparam STATE_HORIZONTAL_SHIFT = 2'd2;

// --- 状态寄存器 (s_clk 上升沿) ---
always @(posedge sclk_p0_w or negedge i_rst_n) begin
    if (!i_rst_n) begin
        state_reg     <= STATE_IDLE;
        freq_sel_prev <= 1'b0;
        exp_fall_sync <= 1'b0;
    end else begin
        state_reg     <= state_next;
        freq_sel_prev <= i_freq_sel;
        exp_fall_sync <= exp_fall_stretched;
    end
end

// 频率切换发生时强制所有计数器复位
assign freq_changed = (freq_sel_prev != i_freq_sel);

always @(posedge sclk_p0_w or negedge i_rst_n) begin
    if (!i_rst_n || freq_changed) begin
        v_counter <= 32'd0;
        h_counter <= 32'd0;
        l_counter <= 32'd0;
    end else begin
        // v_counter: vstate=1 且 exposure=0 时递增,否则复位
        if (state_reg == STATE_VERTICAL_SHIFT && !i_exposure)
            v_counter <= v_counter + 1'b1;
        else
            v_counter <= 32'd0;

        // h_counter: hstate=1 时递增,否则复位
        if (state_reg == STATE_HORIZONTAL_SHIFT)
            h_counter <= h_counter + 1'b1;
        else
            h_counter <= 32'd0;

        // l_counter: h_counter == h_shift_cnt+2 时递增; IDLE 时复位
        if (state_reg == STATE_IDLE)
            l_counter <= 32'd0;
        else if (h_counter == h_shift_cnt + 4)
            l_counter <= l_counter + 1'b1;
    end
end

// exposure 下降沿 (已在 sclk 域同步,来自展宽脉冲)
assign exposure_falling = exp_fall_sync;

// --- 次态逻辑 ---
always @(*) begin
    state_next = state_reg;  // 默认保持
    // 频率切换强制回到 IDLE（优先级最高）
    if (freq_changed) begin
        state_next = STATE_IDLE;
    end else begin
        case (state_reg)
            STATE_IDLE: begin
                if (exposure_falling)
                    state_next = STATE_VERTICAL_SHIFT;
            end
            STATE_VERTICAL_SHIFT: begin
                if (i_exposure)
                    state_next = STATE_IDLE;
                else if (v_counter == v_shift_cnt - 1)
                    state_next = STATE_HORIZONTAL_SHIFT;
            end
            STATE_HORIZONTAL_SHIFT: begin
                if (i_exposure)
                    state_next = STATE_IDLE;
                else if (h_counter == h_shift_cnt + 5) begin
                    if (l_counter == line_cnt)
                        state_next = STATE_IDLE;
                    else
                        state_next = STATE_VERTICAL_SHIFT;
                end
            end
            default: state_next = STATE_IDLE;
        endcase
    end
end

// --- 状态指示信号 ---
assign vstate = (state_reg == STATE_VERTICAL_SHIFT);
assign hstate = (state_reg == STATE_HORIZONTAL_SHIFT);

// ==================================================================
// CCD 驱动信号 — 使能寄存器 + 时钟组合输出
//
// 使能信号在指定同步边沿寄存,组合门控对应的相位时钟:
//
// 垂直组 (v_counter 在有效范围内时使能):
//   P1V      : v_counter 在有效范围内, sclk_p180 上升沿寄存使能 (等效原 sclk_p0 下降沿)
//   P2V,TG   : v_counter 在有效范围内, sclk_p0 上升沿寄存使能
// 水平组 (h_counter 在有效范围内时使能):
//   P1H      : h_counter 在有效范围内, sclk_p180 上升沿寄存使能 (等效原 sclk_p0 下降沿)
//   P2H      : h_counter 在有效范围内, sclk_p180 上升沿寄存使能 (等效原 sclk_p0 下降沿)
//   P3H      : h_counter 在有效范围内, sclk_p180 上升沿寄存使能 (等效原 sclk_p0 下降沿)
//   P4H,SG   : h_counter 在有效范围内, sclk_p0 上升沿寄存使能
//   RG       : h_counter 在有效范围内, sclk_p0 上升沿寄存使能
// ==================================================================
assign o_adcclk  = sclk_p0_w;       // 同相, 50%, 不受任何门控

// 输出复位条件: exposure 拉高 或 状态机处于 IDLE
assign outputs_idle = i_exposure || (state_reg == STATE_IDLE);
assign o_frame_idle = outputs_idle;

// ------------------------------------------------------------------
// 使能寄存器 — 垂直组 (s_clk_p180 上升沿, 等效原 sclk_p0 下降沿)
// ------------------------------------------------------------------
always @(posedge sclk_p180_w or negedge i_rst_n) begin
    if (!i_rst_n)
        p1v_enable <= 1'b0;
    else
        p1v_enable <= !outputs_idle && (v_counter > 0) && (v_counter < v_shift_cnt + 1);
end

assign o_p1v = p1v_enable ? sclk_p270_w : 1'b0;     // 落后 270°

// ------------------------------------------------------------------
// 使能寄存器 — 垂直组 (s_clk_p0 上升沿)
// ------------------------------------------------------------------
always @(posedge sclk_p0_w or negedge i_rst_n) begin
    if (!i_rst_n)
        p2v_tg_enable <= 1'b0;
    else
        p2v_tg_enable <= !outputs_idle && (v_counter > 0) && (v_counter < v_shift_cnt + 1);
end

assign o_p2v_tg = p2v_tg_enable ? sclk_p90_w : 1'b0;     // 落后 90°

// ------------------------------------------------------------------
// 使能寄存器 — 水平组 (s_clk_p180 上升沿, 等效原 sclk_p0 下降沿)
// ------------------------------------------------------------------
always @(posedge sclk_p180_w or negedge i_rst_n) begin
    if (!i_rst_n) begin
        p1h_enable <= 1'b0;
        p2h_enable <= 1'b0;
        p3h_enable <= 1'b0;
    end else begin
        p1h_enable <= !outputs_idle && (h_counter > 0) && (h_counter < h_shift_cnt + 1);
        p2h_enable <= !outputs_idle && (h_counter > 0) && (h_counter < h_shift_cnt + 1);
        p3h_enable <= !outputs_idle && (h_counter > 0) && (h_counter < h_shift_cnt + 1);
    end
end

assign o_p1h = p1h_enable ? sclk_p180_w : 1'b1;          // 落后 180°
assign o_p2h = p2h_enable ? sclk_p270_w : 1'b0;          // 落后 270°
assign o_p3h = p3h_enable ? sclk_p0_w   : 1'b0;          // 同相

// ------------------------------------------------------------------
// 使能寄存器 — 水平组 (s_clk 上升沿)
// ------------------------------------------------------------------
always @(posedge sclk_p0_w or negedge i_rst_n) begin
    if (!i_rst_n) begin
        p4h_sg_enable  <= 1'b0;
        rg_enable      <= 1'b0;
        cdsclk_enable  <= 1'b0;
    end else begin
        p4h_sg_enable  <= !outputs_idle && (h_counter > 0) && (h_counter < h_shift_cnt + 1);
        rg_enable      <= !outputs_idle && (h_counter > 0) && (h_counter < h_shift_cnt + 1);
        cdsclk_enable  <= !outputs_idle && (h_counter > 0) && (h_counter < h_shift_cnt + 1);
    end
end

assign o_p4h_sg = p4h_sg_enable ? sclk_p90_w  : 1'b0;    // 落后 90°
assign o_rg     = rg_enable     ? rg_p90_w    : 1'b1;     // 落后 90°, 25%

assign o_cdsclk1 = cdsclk_enable ? cdsclk1_w   : 1'b0;     // 落后 180°, 12.5%
assign o_cdsclk2 = cdsclk_enable ? cdsclk2_w   : 1'b0;     // 落后 270°, 12.5%

// ==================================================================
// 像素类型指示 (sclk_p180 上升沿同步, 等效原 sclk_p0 下降沿)
// 一行内像素顺序:
//   1..blank_left         : blank  (01)
//   blank_left+1..+bevel   : bevel  (00)
//   +bevel+1..+width       : active (10)
//   +width+1..+bevel_r     : bevel  (00)
//   +bevel_r+1..+blank_r   : blank  (01)
// ==================================================================
assign o_data_valid = data_valid_reg;
assign o_pixel_type = pixel_type_reg;

always @(posedge sclk_p180_w or negedge i_rst_n) begin
    if (!i_rst_n) begin
        data_valid_reg <= 1'b0;
        pixel_type_reg <= 2'b00;
    end else if (hstate && !outputs_idle && (h_counter > 5) && (h_counter <= h_shift_cnt + 6)) begin
        data_valid_reg <= 1'b1;
        if (h_counter <= i_blank_left + 5)
            pixel_type_reg <= 2'b01;                                           // blank
        else if (h_counter <= i_blank_left + i_bevel_left + 5)
            pixel_type_reg <= 2'b00;                                           // bevel
        else if (h_counter <= i_blank_left + i_bevel_left + i_image_width + 5)
            pixel_type_reg <= 2'b10;                                           // active
        else if (h_counter <= i_blank_left + i_bevel_left + i_image_width + i_bevel_right + 5)
            pixel_type_reg <= 2'b00;                                           // bevel
        else
            pixel_type_reg <= 2'b01;                                           // blank
    end else begin
        data_valid_reg <= 1'b0;
        pixel_type_reg <= 2'b00;
    end
end

// ==================================================================
// 像素数据输出 (sclk_p270_w 上升沿同步, 等效原 sclk_p90_w 下降沿)
//
// ADC 输出 8bit 数据, 在 ADCCLK 上升沿和下降沿各变化一次。
// 在 sclk_p90_w 上升沿采样得到高字节, sclk_p270_w 上升沿得到低字节,
// 拼成 16bit 输出: {ADCCLK 上升沿采到的字节, ADCCLK 下降沿采到的字节}
// 采样用 sclk_p90_w (落后 adcclk 90°) 和 sclk_p270_w (落后 270°)
// ==================================================================

always @(posedge sclk_p90_w or negedge i_rst_n) begin
    if (!i_rst_n)
        adc_data_rise <= 8'd0;
    else
        adc_data_rise <= i_adc_data;
end

always @(posedge sclk_p270_w or negedge i_rst_n) begin
    if (!i_rst_n)
        pixel_data_reg <= 16'd0;
    else
        pixel_data_reg <= {adc_data_rise, i_adc_data};
end

assign o_pixel_data = pixel_data_reg;

// ==================================================================
// 帧边界标记 (s_clk 上升沿同步, 与 o_adcclk 同域)
//
// o_frame_start : 帧起始单周期脉冲 (IDLE→VERTICAL_SHIFT 时置位)
// o_frame_end   : 帧结束单周期脉冲 (最后一帧行 HORIZONTAL→IDLE 时置位)
// ==================================================================
always @(posedge sclk_p0_w or negedge i_rst_n) begin
    if (!i_rst_n) begin
        frame_start_reg <= 1'b0;
        frame_end_reg   <= 1'b0;
    end else begin
        // frame_start: IDLE → VERTICAL_SHIFT 时产生单周期脉冲
        if (state_reg == STATE_IDLE && state_next == STATE_VERTICAL_SHIFT)
            frame_start_reg <= 1'b1;
        else
            frame_start_reg <= 1'b0;

        // frame_end: 最后一帧行 HORIZONTAL→IDLE 时产生单周期脉冲
        if (state_reg == STATE_HORIZONTAL_SHIFT && state_next == STATE_IDLE
            && l_counter == line_cnt)
            frame_end_reg <= 1'b1;
        else
            frame_end_reg <= 1'b0;
    end
end

assign o_frame_start = frame_start_reg;
assign o_frame_end   = frame_end_reg;

endmodule
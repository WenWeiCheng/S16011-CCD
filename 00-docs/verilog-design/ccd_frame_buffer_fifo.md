# 帧缓存模块-fifo实现

### 接口

````verilog
module ccd_frame_buf #(
    parameter MAX_FRAME_DEPTH = 131072,  // 子 FIFO 物理深度 (默认 2048×64)
    parameter MAX_FRAMES      = 2        // 最大缓存帧数 (默认 2, 后续 DDR 可扩展)
) (
    // ---- 写侧 (ADCCLK 域) ----
    input  wire         i_adcclk,          // 写时钟 = ADCCLK (≤ 500kHz)
    input  wire         i_rst_n,           // 异步复位, 低有效
    input  wire [15:0]  i_wr_data,         // 像素数据 (来自 ccd_driver.o_pixel_data)
    input  wire         i_wr_en,           // 写使能 (来自 ccd_driver.o_data_valid)
    input  wire [1:0]   i_pixel_type,      // 像素类型 (00=bevel, 01=blank, 10=active)。只有 active 数据写入。
    input  wire         i_frame_start,     // 标记新的一帧。1T 脉冲
    input  wire         i_frame_end,       // 标记帧的结束。1T 脉冲
    input  wire [15:0]  i_image_width,     // 图像宽度 (pixels)
    input  wire [15:0]  i_image_height,    // 图像高度 (pixels)
    input  wire [1:0]   i_read_mode,       // 读出模式: 0=line binning, 1=image

    // ---- 读侧 (FX2 域: i_rd_clk) ----
    input  wire         i_rd_clk,          // 读时钟 (FX2 Slave FIFO, ≤ 48MHz)
    output wire [15:0]  o_fifo_data,       // PP FIFO 读出数据 (16bit, 以帧为单位)
    output wire [FRAME_NUM_W-1:0] o_frame_num,  // 帧缓存中可读帧数
    input  wire         i_fifo_rd_en,      // PP FIFO 读使能
    output wire         o_fifo_last_word,  // 当前读出字是帧最后一字

    // ---- 异常帧 ----
    output wire         o_frame_exception  // 帧异常, 读到有效像素数不等于 i_image_width x i_image_height 的帧
);
````



1. 职责：接收 ccd 数据，保留有效像素数据（image_width x image_height），以帧为单位读写。
2. 采用 ping-pong fifo 缓存：一个写 fifo 和一个读 fifo。写 fifo 和读 fifo 相对独立，写 fifo 工作时，读 fifo 可以正常读出。这里为了简单，**约定读 fifo 不能同时为写 fifo，反之亦然，即不能同时读写一个子 fifo，即使子 fifo 本身支持同时读写**。这样数据以帧为单位传输。
3. 子 fifo 为异步 fifo。写域时钟为 adcclk，不超过 500kHz；读域时钟为外部 EZ-USB Slave FIFO 提供的时钟，不超过 48MHz。



## 读写状态机

![](statemachine/ccd-write-fifo-sm.png)



### 状态定义

**S0：写fifo0，读fifo1**
向 `fifo0` 写入当前帧数据，同时从 `fifo1` 读取上一帧数据。

1. **S1：写fifo1，读fifo0**
   向 `fifo1` 写入当前帧数据，同时从 `fifo0` 读取上一帧数据。
2. **S2：不写，读fifo1**
   暂停写入操作，仅从 `fifo1` 读取数据（等待 `fifo1` 被清空）。
3. **S3：不写，读fifo0**
   暂停写入操作，仅从 `fifo0` 读取数据（等待 `fifo0` 被清空）。

### 状态转换条件（含自环与跨状态转移）

**1. S0（写fifo0，读fifo1）的转换**

- **自环（保持S0）**：满足以下任一条件 → 继续写fifo0、读fifo1，且复位 `fifo0`，并且输出一个 `o_frame_exception` 脉冲：
  - 帧结束（`frame_end↓`，下降沿触发）**且** `fifo1` 非空（`!fifo1_empty`）；
  - `fifo0` 未完成当前帧写入（`!fifo0_frame_ready`）。
- **转S1（写fifo1，读fifo0）**：帧结束（`frame_end↓`）**且** `fifo1` 已空（`fifo1_empty`）**且** `fifo0` 完成当前帧写入（`fifo0_frame_ready`）→ 切换为写fifo1、读fifo0。
- **转S2（不写，读fifo1）**：`fifo0` 完成当前帧写入（`fifo0_frame_ready`）**且** `fifo1` 非空（`!fifo1_empty`）→ 暂停写入，仅读fifo1。

**2. S1（写fifo1，读fifo0）的转换**

- **自环（保持S1）**：满足以下任一条件 → 继续写fifo1、读fifo0，且复位 `fifo1`，并且输出一个 `o_frame_exception` 脉冲：
  - 帧结束（`frame_end↓`）**且** `fifo0` 非空（`!fifo0_empty`）；
  - `fifo1` 未完成当前帧写入（`!fifo1_frame_ready`）。
- **转S0（写fifo0，读fifo1）**：帧结束（`frame_end↓`）**且** `fifo0` 已空（`fifo0_empty`）**且** `fifo1` 完成当前帧写入（`fifo1_frame_ready`）→ 切换为写fifo0、读fifo1。
- **转S3（不写，读fifo0）**：`fifo1` 完成当前帧写入（`fifo1_frame_ready`）**且** `fifo0` 非空（`!fifo0_empty`）→ 暂停写入，仅读fifo0。

**3. S2（不写，读fifo1）的转换**

- **转S1（写fifo1，读fifo0）**：`fifo1` 被清空（`fifo1_empty`）→ 恢复写fifo1、读fifo0（此时 `fifo1` 可接收新帧写入）。

**4. S3（不写，读fifo0）的转换**

- **转S0（写fifo0，读fifo1）**：`fifo0` 被清空（`fifo0_empty`）→ 恢复写fifo0、读fifo1（此时 `fifo0` 可接收新帧写入）。

### 关键信号说明

- `frame_end↓`：**帧结束信号下降沿**，标志一帧数据传输结束，用于判断当前帧传输状态。
- `fifoX_frame_ready`：`fifoX` **当前帧写入传输标志**（完成后为1，未完成时为0），具体状态转换见”帧状态“一节定义。当有效像素（`i_pixel_type=2'b10`）计数等于 `i_frame_depth` 时视为传输完成为 1。少于、超过设定值，都不为 1，说明传输异常，下次 `frame_end` 时不轮换写 fifo，直接复位，重新写。
- `fifoX_empty`：`fifoX`（X=0/1）**空标志**（空时为1，非空时为0）。
- `reset fifoX`：在自环状态下，对正在写入的 `fifoX` 执行**复位操作**（确保下一帧写入前FIFO状态干净）

### 其它说明

1. 读写状态与系统时钟同步
2. 使用读写状态路由写入数据、读出数据和相应的读写标志。



## 帧最后一字指示 (o_fifo_last_word)

`o_fifo_last_word` 用于**提前告知**读者当前读出字是当前帧的最后一字, 使 `ccd_frame_tx` 能同步将 `o_frame_done_n` 与最后一字一同送出。

- 来源: 当前活跃子 FIFO 的 `o_almost_empty` (由 `async_fifo` 提供)
- 时钟域: `i_rd_clk` (读时钟域), 上升沿更新
- 路由: 与 `o_fifo_data` 一样经 `rd_sel` MUX 选择

**工作原理**:
1. `async_fifo` 在上升沿计算 `bin2gray(rd_ptr+1) == wr_gray_synced`, 若成立则当前拍读出会使 FIFO 变空 → 当前字是最后一字
2. `ccd_frame_buf` 将当前读取子 FIFO 的 `o_almost_empty` 直通到 `o_fifo_last_word`
3. 下游 `ccd_frame_tx` 在上升沿采样该信号, 与数据同步进入管道, 在下降沿输出最后一字时同时拉低 `o_frame_done_n`



## 帧状态

![](statemachine/ccd-frame-state-sm.png)

### 状态定义

1. **`fifoX frame empty`（帧空状态）**
   fifo 中无有效帧数据（或当前帧已被完全读取），处于“等待新帧写入”的状态。
2. **`fifoX frame ready`（帧就绪状态）**
   FIFO中已写入完整的一帧数据，处于“等待外部读取”的状态。
3. **`fifoX frame exception`（FIFO帧异常）**
   检测到**帧长度错误**（帧结束信号到来时，像素计数与预设帧深度不匹配），进入“错误标记/处理”状态。



### 状态转换条件

1. `frame empty` **↔** `frame ready`**（正常帧写入/读取流程）**

- **`empty` → `ready`（帧写入完成）**：
  当 **“帧结束信号上升沿”**（`frame_end↑`）触发，且 **“像素计数等于预设帧深度”**（`pixel_count = i_frame_depth`）时，确认一帧数据完整写入，状态切换为`ready`。
- **`ready` → `empty`（帧读取完成）**：
  当 **“FIFO空信号上升沿”**（`fifo_empty↑`）触发时，确认FIFO内的帧数据已被完全读取，状态复位为`empty`。

2. `frame empty` **↔** `frame exception`**（异常检测与恢复流程）**

- **`empty` → `exception`（帧长度错误检测）**：
  当 **“帧结束信号上升沿”**（`frame_end↑`）触发，但 **“像素计数不等于预设帧深度”**（`pixel_count != i_frame_depth`）时，判定帧数据长度异常（过短或过长），状态切换为`exception`。
- **`exception` → `empty`（异常恢复）**：
  当 **“帧结束信号下降沿”**（`frame_end↓`）触发时，系统尝试复位异常状态，重新回到`empty`状态以等待下一帧的正确写入（隐含逻辑：通过帧结束信号的下降沿清除异常标记，重启帧接收流程）。



## 端口定义

```verilog
module ccd_pp_fifo #(
    parameter MAX_FRAME_DEPTH = 131072  // 子 FIFO 物理深度 (默认 2048×64)
) (
    // ---- 写侧 (ADCCLK 域) ----
    input  wire         i_adcclk,          // 写时钟 = ADCCLK (≤ 500kHz)
    input  wire         i_rst_n,           // 异步复位, 低有效
    input  wire [15:0]  i_wr_data,         // 像素数据 (来自 ccd_driver.o_pixel_data)
    input  wire         i_wr_en,           // 写使能 (来自 ccd_driver.o_data_valid)
    input  wire [1:0]   i_pixel_type,      // 像素类型 (00=bevel, 01=blank, 10=active)
    input  wire         i_frame_start,     // 标记新的一帧
    input  wire         i_frame_end,       // 标记帧的结束
    input  wire [31:0]  i_frame_depth,     // 运行时帧深度 (有效像素个数, 如 65536 / 131072)

    // ---- 读侧 (FX2 域: i_rd_clk) ----
    input  wire         i_rd_clk,          // 读时钟 (FX2 Slave FIFO, ≤ 48MHz)
    output wire [15:0]  o_fifo_data,       // PP FIFO 读出数据 (16bit, 以帧为单位)
    output wire         o_fifo_empty,      // PP FIFO 空 (0 帧)
    output wire         o_fifo_half_full,  // PP FIFO 半满 (1 帧)
    output wire         o_fifo_full,       // PP FIFO 满 (2 帧)
    input  wire         i_fifo_rd_en,      // PP FIFO 读使能
    output wire         o_rd_fifo_sel,     // 当前读 FIFO 选择 (0=读fifo0, 1=读fifo1)
    output wire         o_fifo_last_word,  // 当前读出字是帧最后一字 (来自子 FIFO o_almost_empty)
    
    // ---- 异常帧 ----
    output wire 		o_frame_exception  // 帧异常，读到有效像素数少于 i_frame_depth 的帧
);
```








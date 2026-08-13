## 帧发送模块

1. 职责：适当时机（如主机请求），将一帧数据发出去（通常是给 EZ-USB Slave FIFO）。
1. 接中和发送接口也为 FIFO，但发送接口主要是适配 EZ-USB Slave FIFO。



### 发送逻辑

![](statemachine/ccd-frame-tx-sm.png)

### 状态定义

1. **`idle`（空闲状态）**
   - **含义**：系统的初始或复位状态。此时没有数据传输任务，系统处于静止等待模式。
   - **行为**：保持当前状态，直到收到启动信号或被强制复位。
2. **`wait`（等待状态）**
   - **含义**：已接收到启动指令，正在等待数据源准备好。
   - **行为**：监测系统内部“帧缓冲区”是否有数据，同时检查下游“从设备FIFO”是否具备接收能力。只有当两者都满足时，才会进入发送阶段。
3. **`transmit`（发送/传输状态）**
   - **含义**：正在进行数据传输操作。
   - **行为**：将帧缓冲区的数据发送给从设备。此状态会一直持续，直到触发特定的结束条件（如缓冲区排空）。

### 状态转换条件

1. `idle` **状态的转换**

- 自环（保持 `idle`）：
  - **条件**：`reset`（复位信号有效）。
  - **说明**：只要复位信号存在，系统就强制停留在空闲状态，清除所有活动。
- 跳转至 `wait`：
  - **条件**：`start↓`（启动信号的下降沿）。
  - **说明**：检测到启动脉冲的下降沿，标志着一次新的传输任务开始，系统离开空闲态进入准备阶段。

2. `wait` **状态的转换**

- 跳转至 `transmit`：
  - **条件**：`frame buf non empty` **且** `slave fifo ready`。
  - 说明：这是一个“握手”过程。必须同时满足两个条件：
    1. **源端就绪**：帧缓冲区里有数据（非空）。
    2. **宿端就绪**：接收端的从设备FIFO可以接收数据（Ready）。
       只有双方都准备好了，才开始传输。

3. `transmit` **状态的转换**

- 跳转回 `idle`：
  - **条件**：`i_frame_fifo_last_word == 1`。
  - 说明：`i_frame_fifo_last_word` 与数据管道同步，表示当前送入 Slave FIFO 的字是帧最后一字，传输完成。此信号来源于 `ccd_frame_buf.o_fifo_last_word`，后者由子 FIFO 的 `o_almost_empty` 驱动，在最后一读时预判拉高。

### 发送时序

1. 从 `ccd-frame-buf` fifo 中读数据，时钟使用 `i_ext_clk`，**下降沿**更新 `o_frame_fifo_rd_en`，async_fifo 在下一**上升沿**采样。
2. 当 `o_data_valid_n=0`， EZ-USB Slave FIFO 在 `i_ext_clk` 的下降沿同步读入 `o_slave_fifo_data_valid_n`, `o_frame_done_n` 和 `o_slave_fifo_data`。
3. 当 `o_data_valid_n=0 & o_frame_done_n=0`， EZ-USB Slave FIFO 在 `i_ext_clk` 的上升沿将接收此时的数据视为最后一个，然后打包发送给主机，同时拉低 `i_slave_fifo_full_n`（即使本来 Slave FIFO 未满）。`o_frame_done_n` 由 `i_frame_fifo_last_word` 驱动，与最后一字同步。

```
module ccd_frame_tx (
    // 系统接口
    input  wire         i_ext_clk,               // 读时钟 (FX2 侧时钟)
    input  wire         i_rst_n,
    // PP FIFO 读接口，以帧为单位，宽度为 16bit，深度为 2
    input  wire [15:0]  i_frame_fifo_data,
    input  wire         i_frame_fifo_empty,
    input  wire 		i_frame_fifo_half_full,
    input  wire 		i_frame_fifo_full,
    input  wire 		i_frame_fifo_last_word,   // 当前读出字是帧最后一字
    output wire         o_frame_fifo_rd_en,
    // FX2 Slave FIFO 接口
    output wire [15:0]  o_slave_fifo_data,
    output wire         o_slave_fifo_data_valid_n,
    input  wire         i_slave_fifo_empty_n,     // FX2 侧 FIFO 空反馈
    input  wire         i_slave_fifo_full_n,      // FX2 侧 FIFO 满反馈
    // 帧控制
    input  wire         i_frame_start,            // 开始一帧数据传输
    output wire         o_frame_done_n            // 一帧发送已完成
);
```

| 信号                                | 描述                       | 时钟域                              |
| ----------------------------------- | -------------------------- | ----------------------------------- |
| i_frame_fifo_data                   | 读出 pp-fifo 数据          | i_ext_clk；上升沿同步               |
| i_frame_fifo_empty, half_full, full | pp-fifo 标志               | i_ext_clk；上升沿同步               |
| i_frame_fifo_last_word              | 当前读出字是帧最后一字     | i_ext_clk；上升沿同步               |
| o_frame_fifo_rd_en                  | pp-fifo 读控制             | i_ext_clk；上升沿同步               |
| o_slave_fifo_data                   | FX2 侧数据                 | i_ext_clk_n；上升沿同步             |
| o_slave_fifo_data_valid_n           | FX2 侧 FIFO 写使能，低有效 | i_ext_clk_n；上升沿同步；低电平有效 |
| i_slave_fifo_empty_n                | FX2 侧 FIFO 空反馈，低有效 | i_ext_clk；上升沿同步               |
| i_slave_fifo_full_n                 | FX2 侧 FIFO 满反馈，低有效 | i_ext_clk；上升沿同步               |
| i_frame_start                       | 开始一帧数据传输           | i_ext_clk；上升沿同步               |
| o_frame_done_n                      | 一帧数据结束，低有效       | i_ext_clk ；下降沿同步              |


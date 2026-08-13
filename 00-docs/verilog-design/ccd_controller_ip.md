# ccd_controller AXI4-Lite IP 寄存器

## 模块职责

`ccd_controller` 是 CCD 控制器的 AXI4-Lite 可编程外设 IP：将 `ccd_ddr`（CCD 时序驱动 + DDR3 帧缓存 + FX2 帧发送）封装为寄存器可配置外设，供 MicroBlaze 等 CPU 配置采集参数、触发帧发送、读取状态并接收中断。主要能力：

- **CCD 时序驱动**：产生垂直/水平移位时钟（支持 line binning 与 image 两种读出模式，SCLK 100/500kHz 可选）、RG 及 CDSCLK 采样时序；垂直时序为 2 相时钟，水平时序为 4 相时钟。
- **数据采集与缓存**：采集 8bit ADC 数据，剔除 bevel 像素，将有效像素经 AXI4 Master（128bit）写入 DDR3 帧缓存；
- **帧发送**：经 FX2 Slave FIFO 输出 16bit 像素流，并提供最后一字标志 `o_slave_fifo_data_last_n`，供 FX2 将未满 FIFO 打包经 USB 上传；
- **CPU 接口**：寄存器配置（CTRL / IMG_SIZE / BEVEL_BLANK / TRIGGER）、状态查询（STATUS / FRAME_NUM）与中断（帧异常、发送完成）。

```
                 ┌───────────────────────────────────────────┐
   CPU (AXI-Lite)│  ccd_controller_v1_0                      │
   s00_axi_* ──→ │  ┌──────────┐   ┌────────────────────┐   │
                 │  │ 寄存器组  │──→│                    │   │
                 │  │ CTRL     │   │   ccd_ddr          │──→│ CCD 传感器
                 │  │ IMG_SIZE │   │  ┌────────────┐    │   │
                 │  │ BEVEL_   │   │  │ ccd_driver │    │   │
                 │  │ BLANK    │   │  ├────────────┤    │──→│ DDR3 (MIG)
                 │  │ TRIGGER  │   │  │ frame_buf  │    │   │
                 │  ├──────────┤   │  ├────────────┤    │   │
                 │  │ 状态/中断 │←──│  │ frame_tx   │    │──→│ FX2 Slave FIFO
                 │  │ STATUS   │   │  └────────────┘    │   │
                 │  │ FRAME_NUM│   │                    │   │
                 │  │ INTR_EN  │   │                    │   │
                 │  │ INTR_STS │   └────────────────────┘   │
                 │  └──────────┘                            │
   intr ────────→│  (中断输出)                              │
                 └───────────────────────────────────────────┘
```

## 模块接口

### 参数

实例化 ip 时可配置以下参数：

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `MAX_FRAME_DEPTH` | 131072 | 每帧最大像素数（每个像素 2 字节） |
| `MAX_FRAMES` | 8 | DDR3 中最大缓存帧数（帧计数 `FRAME_NUM` 为 32bit，上限远大于该值；可在 BD 中调整） |
| `C_S00_AXI_DATA_WIDTH` | 32 | AXI 数据宽度 |
| `C_S00_AXI_ADDR_WIDTH` | 6 | AXI 地址宽度（64 字节地址空间） |

### 端口

| 端口分组 | 信号 | 方向 | 说明 |
|----------|------|------|------|
| **AXI4-Lite** | `s00_axi_*` | — | 标准 AXI4-Lite 从机接口（时钟 `s00_axi_aclk` = 100MHz） |
| **中断** | `intr` | 输出 | 中断请求，连 MicroBlaze INTC |
| **CCD 驱动** | `o_adcclk` `o_p1v` `o_p2v_tg` `o_p1h` `o_p2h` `o_p3h` `o_p4h_sg` `o_rg` `o_cdsclk1` `o_cdsclk2` | 输出 | CCD 传感器驱动信号 |
| **ADC 数据** | `i_adc_data[7:0]` | 输入 | ADC 采样数据 |
| **FX2 Slave FIFO** | `i_rd_clk` `i_rd_clk_n` `i_slave_fifo_empty_n` `i_slave_fifo_full_n` `o_slave_fifo_data[15:0]` `o_slave_fifo_data_wr_en_n` `o_slave_fifo_data_last_n` `o_slave_fifo_clk` | — | FX2 帧发送接口（wr_en_n=写使能低有效，last_n=最后一字标志，clk=读时钟扇出） |
| **MIG/DDR3** | `i_ui_clk` `i_mmcm_locked` `i_init_calib_complete` `M_AXI_*` | — | MIG 接口 + AXI4 Master（128bit 数据，连 MIG S_AXI） |

## 寄存器映射总表

| 偏移 | 名称 | 访问 | Bit map |
|------|------|:---:|------|
| `0x00` | `CTRL` | R/W | `[0]` exposure, `[1]` freq_sel, `[2]` mock_mode, `[4:3]` read_mode, `[11:5]` cdsclk_delay, `[12]` soft_reset（写 1 触发自清脉冲，读回 0）, `[31:13]` 保留 |
| `0x04` | `IMG_SIZE` | R/W | `[15:0]` image_width, `[31:16]` image_height |
| `0x08` | `BEVEL_BLANK` | R/W | `[3:0]` bevel_left, `[7:4]` bevel_top, `[11:8]` bevel_right, `[15:12]` bevel_bottom, `[19:16]` blank_l, `[23:20]` blank_r, `[31:24]` 保留 |
| `0x0C` | `TRIGGER` | W | `[0]` tx_start（写 1 触发，读回 0）, `[31:1]` 保留 |
| `0x10` | `STATUS` | R | `[8]` exception, `[15:9]` exception_cnt, `[16]` ddr3_done, `[31:0]` 其余保留 |
| `0x14` | `INTR_EN` | R/W | `[8]` exception_en, `[9]` tx_done_en, `[10]` frame_written_en, `[31:11]` 保留 |
| `0x18` | `INTR_STS` | R/W1C | `[8]` exception_pending, `[9]` tx_done_pending, `[10]` frame_written_pending, `[31:11]` 保留 |
| `0x1C` | `FRAME_NUM` | R | `[31:0]` frame_num（帧缓存可读帧数，实时，32bit） |
| `0x20` | 保留 | R/W | — |

## 寄存器详解

### `0x00` CTRL — 采集控制（R/W，复位 0）

| 位 | 字段 | 说明 |
|----|------|------|
| `[0]` | `exposure` | CCD 曝光/读出控制：`1`=曝光/积分中（驱动输出空闲，状态机回 IDLE）；`0`=下降沿触发读出（读出完成后回到 IDLE） |
| `[1]` | `freq_sel` | SCLK 频率：`0`=100kHz，`1`=500kHz |
| `[2]` | `mock_mode` | 调试模式：`1`=屏蔽 ADC，输出自增虚拟像素 |
| `[4:3]` | `read_mode` | 读出模式：`0`=line binning，`1`=image |
| `[11:5]` | `cdsclk_delay` | CDSCLK 微调延时，单位系统时钟周期 |
| `[12]` | `soft_reset` | 写 `1` 触发软复位（总复位整条 CCD 流水线），自动清 `0`，读回恒 `0`，不存储 |
| `[31:13]` | — | 保留 |

### `0x04` IMG_SIZE — 图像尺寸（R/W，复位 0）

| 位 | 字段 | 说明 |
|----|------|------|
| `[15:0]` | `image_width` | 图像宽度（像素） |
| `[31:16]` | `image_height` | 图像高度（像素） |

### `0x08` BEVEL_BLANK — 消隐/空白（R/W，复位 0）

| 位 | 字段 | 说明 |
|----|------|------|
| `[3:0]` | `bevel_left` | 左侧消隐 |
| `[7:4]` | `bevel_top` | 顶部消隐 |
| `[11:8]` | `bevel_right` | 右侧消隐 |
| `[15:12]` | `bevel_bottom` | 底部消隐 |
| `[19:16]` | `blank_left` | 左侧空白 |
| `[23:20]` | `blank_right` | 右侧空白 |
| `[31:24]` | — | 保留 |

### `0x0C` TRIGGER — 触发控制（只写，读恒 0）

| 位 | 字段 | 说明 |
|----|------|------|
| `[0]` | `tx_start` | 写 `1` → 硬件产生展宽至 16 周期的脉冲（≈160ns @100MHz）→ 自动清 `0` |

> 触发脉冲展宽确保 `i_rd_clk`（25~48MHz）域可靠采样到上升沿。

### `0x10` STATUS — 实时状态（只读）

| 位 | 字段 | 说明 |
|----|------|------|
| `[8]` | `exception` | 帧异常标志（已 CDC 同步，实时） |
| `[15:9]` | `exception_cnt` | 帧异常计数（7bit，饱和至 127，复位清零） |
| `[16]` | `ddr3_done` | DDR3 校准完成（`mmcm_locked && init_calib_complete`，已 CDC 同步） |
| `[31:0]` | — | 其余保留 |

> `exception_cnt` 为累计计数（每次异常 +1），`exception` 为实时脉冲标志，两者配合可诊断帧长异常。
> 帧计数已移入独立寄存器 `FRAME_NUM`（`0x1C`），STATUS 不再携带帧计数。

### `0x1C` FRAME_NUM — 帧缓存帧数（只读）

| 位 | 字段 | 说明 |
|----|------|------|
| `[31:0]` | `frame_num` | 帧缓存中可读帧数（32bit，实时） |

- 独立 32bit 寄存器（区别于旧版将帧计数挤在 STATUS[7:0]），帧数上限仅受 `MAX_FRAMES` 参数约束（≤ 2³²−1），支持扩大缓存。
- 来自 `i_rd_clk` 域（`frames_in_fifo` 计数，饱和至 `MAX_FRAMES`），未做跨域同步（与旧版 STATUS[7:0] 行为一致：数值每帧变化一次，撕裂读概率极低且自愈）。注意 `o_frame_num` 在 rd-fifo 为空时报 0，属正常现象（帧数据已取尽时）。
- 写操作被忽略（只读）。

### `0x14` INTR_EN — 中断使能（R/W，复位 0）

| 位 | 字段 | 说明 |
|----|------|------|
| `[8]` | `exception_en` | `1`：帧异常产生中断 |
| `[9]` | `tx_done_en` | `1`：帧发送完成产生中断 |
| `[10]` | `frame_written_en` | `1`：一帧完整写入 DDR（=CCD 读出时序完成，`frame_num` +1）产生中断 |
| `[31:11]` | — | 保留 |

### `0x18` INTR_STS — 中断状态（R/W1C）

| 位 | 字段 | 说明 |
|----|------|------|
| `[8]` | `exception_pending` | 帧异常锁存：`exception` 上升沿置 `1`；写 `1` 清除 |
| `[9]` | `tx_done_pending` | 帧发送完成锁存：`o_tx_last_n` 下降沿置 `1`；写 `1` 清除 |
| `[10]` | `frame_written_pending` | 帧写入完成锁存：`o_frame_written` 上升沿置 `1`；写 `1` 清除 |
| `[31:11]` | — | 保留 |

> **W1C**（Write-1-to-Clear）：向对应位写 `1` 清除该位，写 `0` 无影响。CPU 无需读-改-写。

## 中断逻辑

```verilog
intr = (exception_pending && INTR_EN[8])
    || (tx_done_pending    && INTR_EN[9])
    || (frame_written_pending && INTR_EN[10]);
```

| 中断源 | 触发边沿 | 源时钟域 | 同步方式 | 使能 | 清除 |
|--------|----------|----------|----------|------|------|
| `exception` | 上升沿 | `i_ui_clk`（MIG） | 2-FF 同步器 + 边沿检测 | `INTR_EN[8]` | 写 `INTR_STS[8]=1` |
| `tx_done` | `o_tx_last_n` 下降沿 | `i_rd_clk`（FX2） | 2-FF 同步器 + 边沿检测 | `INTR_EN[9]` | 写 `INTR_STS[9]=1` |
| `frame_written` | `o_frame_written` 上升沿 | `i_rd_clk`（FX2） | 2-FF 同步器 + 边沿检测 | `INTR_EN[10]` | 写 `INTR_STS[10]=1` |

> `frame_written` 与 `frame_num` +1 是同一硬件事件（帧完整写入 DDR），即 CCD 读出时序完成；软件据此推进 live/burst 连续采集，无需轮询。

## 跨时钟域（CDC）与复位

### 时钟域

| 域 | 时钟 | 用途 |
|----|------|------|
| AXI | `s00_axi_aclk`（100MHz） | 寄存器组、中断、触发脉冲 |
| ADC 像素 | `o_adcclk`（100/500kHz） | 像素采集 |
| DDR3 UI | `i_ui_clk`（MIG 输出） | AXI 写 DDR |
| FX2 读 | `i_rd_clk`（48MHz） | 帧发送 |

### CDC 同步

所有从其他时钟域进入 AXI 域的信号均经 **2-FF 同步器**：

| 信号 | 源域 → 目标域 | 同步 |
|------|---------------|------|
| `i_ddr3_init_done` | MIG → AXI | 2-FF |
| `o_frame_exception` | ui_clk → AXI | 2-FF + 边沿检测 |
| `o_tx_last_n` | rd_clk → AXI | 2-FF + 边沿检测 |
| `o_frame_written` | rd_clk → AXI | 2-FF + 边沿检测 |
| 触发脉冲 `tx_frame_start` | AXI → rd_clk | 16 周期展宽（160ns） |
| 软复位脉冲 `soft_rst_cnt` | AXI → ccd_ddr（异步复位） | 16 周期展宽（~160ns），断言异步、释放由 ccd_ddr 展宽 |
| `frame_num`（FRAME_NUM 寄存器） | rd_clk → AXI | 无（原 STATUS[7:0] 行为，频率极低，撕裂读自愈） |

### 复位策略

- `ccd_ddr` 在 DDR3 校准完成前（`mmcm_locked && init_calib_complete`）始终对外保持复位（其内部展宽 ~41µs），防止提前发起 AXI 写事务。
- AXI 层将系统复位与软复位脉冲合并为 `ccd_ddr` 的主复位输入：

  ```verilog
  ccd_ddr_rst_n = S_AXI_ARESETN && (soft_rst_cnt == 0);
  ```

  - `S_AXI_ARESETN`：系统复位。
  - `soft_rst_cnt`：写 `CTRL[12]=1` 载入的自清脉冲计数器（约 16 个 AXI 周期）。期间拉低主复位 → `ccd_ddr` 异步复位断言 + 展宽释放，复位整条 CCD 流水线（driver / frame_buf / tx）。
- 所有内部子模块使用异步复位（低有效），断言无跨域风险；释放由 `ccd_ddr` 展宽同步。

### 图像参数变更软复位（软件控制）

帧缓存采用**固定帧长度**（复位释放后锁定一次）。图像参数（`CTRL[4:3]` read_mode、`IMG_SIZE` width/height）变化**不再由硬件自动检测复位**，改由软件在写参数后显式触发 `CTRL[12]` 软复位：

- 软复位经 `ccd_ddr` 主复位展宽（~41µs）复位帧缓存控制器与 AXI adapter：清空 wr/rd FIFO、块指针与帧计数（`frame_num` 归 0），释放后按新参数重新锁定帧长度。
- **软件时序**（协议层 `Apply_ReadMode` / `Apply_ImageSize`）：先 `Ccd_Stop()` 停止采集/发送 → 写参数寄存器 → `CcdController_SoftReset()`（写 `CTRL[12]=1`，自清，无需再写 0）。
- `ccd_driver`（CCD 时序）与 `ccd_frame_tx`（帧发送）随总复位一并复位（整条流水线重启），复位时机由软件掌控。
- 开机后必须先"写参数 + 软复位"帧长才会锁定为有效值（硬件不再自动重锁）。

## 从属 IP 寄存器说明

| IP | 类型 | 用户可见寄存器 |
|----|------|----------------|
| `ccd_controller_v1_0` | 自定义 AXI 外设 | ✅ 上文 0x00~0x20 |
| `wr_ddr3_fifo` / `rd_ddr3_fifo` | FIFO Generator 13.2 | ❌ 纯数据通道 |

### FIFO（wr/rd_ddr3_fifo）

纯数据 FIFO，无寄存器：

| 参数 | wr_ddr3_fifo | rd_ddr3_fifo |
|------|--------------|--------------|
| 方向 | ADC 16bit → DDR3 128bit | DDR3 128bit → FX2 16bit |
| 宽度 | 16 → 128 | 128 → 16 |
| 深度 | 512 → 64 | 64 → 512 |

## 软件使用示例

```c
// 假设基地址 0x44A00000
#define CCDC_BASE   0x44A00000UL
#define REG_CTRL    (CCDC_BASE + 0x00)
#define REG_IMG     (CCDC_BASE + 0x04)
#define REG_BEVEL   (CCDC_BASE + 0x08)
#define REG_TRIG    (CCDC_BASE + 0x0C)
#define REG_STATUS  (CCDC_BASE + 0x10)
#define REG_IRQ_EN  (CCDC_BASE + 0x14)
#define REG_IRQ_STS (CCDC_BASE + 0x18)
#define REG_FRAME_NUM (CCDC_BASE + 0x1C)

// 初始化：配置图像 8×2, line binning
Xil_Out32(REG_IMG,   (2 << 16) | 8);        // width=8, height=2
Xil_Out32(REG_BEVEL, 0x00111111);           // 各消隐=1
Xil_Out32(REG_CTRL,  0x00001000);           // 软复位: 重锁帧长并清空帧缓存 (写1自清)
Xil_Out32(REG_CTRL,  0x00000001);           // exposure=1: 曝光中 (驱动输出空闲)
Xil_Out32(REG_CTRL,  0x00000000);           // exposure=0: 下降沿触发读出 (line binning)

// 触发帧发送
Xil_Out32(REG_TRIG,  0x1);

# 轮询帧缓存状态
if (Xil_In32(REG_FRAME_NUM) > 0) {          // frame_num > 0
    // ... 触发发送 / 读取
}

// 中断方式
Xil_Out32(REG_IRQ_EN, 0x200);               // 使能 tx_done 中断
// ISR 中:
if (Xil_In32(REG_IRQ_STS) & 0x200) {
    Xil_Out32(REG_IRQ_STS, 0x200);          // W1C 清除
}
```

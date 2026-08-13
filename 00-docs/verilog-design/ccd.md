# CCD 控制器顶层模块 (`ccd`)

## 模块职责

`ccd` 是 CCD 控制器的顶层模块，将三个子模块整合为完整的数据通路：

```
                    ┌──────────┐   像素数据    ┌──────────────┐  帧数据   ┌───────────┐
  ADC 数据 ───────→  │          │ ──────────→ │              │ ───────→ │           │ ─────→ EZ-USB
  控制参数 ───────→  │ ccd_     │  控制/状态    │ ccd_frame_   │  标志     │ ccd_      │        Slave
  曝光信号 ───────→  │ driver   │ ──────────→ │ buf           │ ───────→ │ frame_tx  │        FIFO
                    │          │ ←────────── │ (乒乓帧缓存)   │          │           │
                    └──────────┘   帧起止     └──────────────┘   读使能   └───────────┘
                       ▲ CCD 驱动时钟/相位信号输出到传感器
                       │
                    CCD 传感器
```

| 子模块 | 文件 | 功能简述 |
|--------|------|----------|
| `ccd_driver` | `rtl/ccd_driver.v` | 产生 CCD 垂直/水平移位时序、ADC 采样时钟；解析 ADC 数据并标记像素类型 |
| `ccd_frame_buf` | `rtl/ccd_frame_buf.v` | 乒乓 FIFO 帧缓存，以帧为单位缓冲像素数据；检测帧长异常 |
| `ccd_frame_tx` | `rtl/ccd_frame_tx.v` | 将帧缓存中的像素数据转发至 EZ-USB Slave FIFO，适配 FX2 接口时序 |

## 模块接口

### 参数

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `MAX_FRAME_DEPTH` | 131072 | 子 FIFO 物理深度（默认 2048×64） |

### 端口

| 端口分组 | 信号 | 位宽 | 方向 | 说明 |
|----------|------|------|------|------|
| **系统** | `i_clk` | 1 | 输入 | 系统时钟 100 MHz |
| | `i_rst_n` | 1 | 输入 | 异步复位，低有效 |
| **CCD 控制** | `i_exposure` | 1 | 输入 | 曝光信号（下降沿启动读出） |
| | `i_freq_sel` | 1 | 输入 | SCLK 频率选择：0→100kHz，1→500kHz |
| | `i_cdsclk_delay` | 7 | 输入 | CDSCLK 微调延时，单位系统时钟周期 |
| **图像参数** | `i_image_width` | 16 | 输入 | 图像宽度（像素） |
| | `i_image_height` | 16 | 输入 | 图像高度（像素） |
| | `i_bevel_left/top/right/bottom` | 4×4 | 输入 | 四边 bevel 像素数 |
| | `i_blank_left/right` | 4×2 | 输入 | 左右 blank 像素数 |
| | `i_read_mode` | 2 | 输入 | 读出模式：0=line binning，1=image |
| **ADC 数据** | `i_adc_data` | 8 | 输入 | ADC 采样数据 |
| **CCD 驱动输出** | `o_adcclk, o_p1v, o_p2v_tg, o_p1h~o_p4h_sg, o_rg, o_cdsclk1/2` | 1×10 | 输出 | CCD 传感器驱动时钟/相位信号 |
| **Slave FIFO** | `i_rd_clk` | 1 | 输入 | FX2 Slave FIFO 读时钟（≤ 48 MHz） |
| | `i_tx_frame_start` | 1 | 输入 | 帧发送触发（下降沿启动） |
| | `i_slave_fifo_empty_n` | 1 | 输入 | FX2 Slave FIFO 空（低有效） |
| | `i_slave_fifo_full_n` | 1 | 输入 | FX2 Slave FIFO 满（低有效） |
| | `o_slave_fifo_data` | 16 | 输出 | 输出到 Slave FIFO 的数据 |
| | `o_slave_fifo_data_valid_n` | 1 | 输出 | 数据有效（低有效） |
| | `o_frame_done_n` | 1 | 输出 | 帧发送完成（低有效） |
| **帧缓存状态** | `o_frame_num` | 2 | 输出 | 帧缓存中可读帧数：0=空，1=一帧，2=两帧 |
| **异常** | `o_frame_exception` | 1 | 输出 | 帧异常标志 |

## 内部数据流

### CCD 驱动 → 帧缓存

`ccd_driver` 将 ADC 串行数据拼合为 16-bit 像素，连同像素类型标签一并输出：

| 内部信号 | 位宽 | 说明 |
|----------|------|------|
| `data_valid_w` | 1 | 像素数据有效（与 `adcclk` 下降沿同步） |
| `pixel_type_w` | 2 | 像素类型：00=bevel，01=blank，10=active |
| `pixel_data_w` | 16 | 16-bit 像素数据 |
| `frame_start_w` | 1 | 帧开始脉冲 |
| `frame_end_w` | 1 | 帧结束脉冲 |

### 帧缓存 → 帧发送

`ccd_frame_buf` 输出帧深度 `frame_depth_w`（取决于读出模式），并将乒乓 FIFO 读侧接口暴露给 `ccd_frame_tx`：

| 内部信号 | 位宽 | 说明 |
|----------|------|------|
| `fifo_data_w` | 16 | 读出像素数据 |
| `fifo_empty_w` | 1 | 帧缓存空 |
| `fifo_half_full_w` | 1 | 帧缓存半满（有 1 帧） |
| `fifo_full_w` | 1 | 帧缓存满（有 2 帧） |
| `fifo_last_word_w` | 1 | 当前字为帧最后一字 |
| `fifo_rd_en_w` | 1 | 帧缓存读使能（由 `ccd_frame_tx` 驱动） |

`o_frame_num` 由三个标志编码得到：

| `o_frame_num` | 帧数 | 对应标志 |
|:---:|:---:|:---|
| 00 | 0 帧（空） | `fifo_empty` |
| 01 | 1 帧 | `fifo_half_full` |
| 10 | 2 帧（满） | `fifo_full` |

```verilog
assign o_frame_num = {fifo_full_w, fifo_half_full_w};
```

### 帧深度计算

```
frame_depth = (i_read_mode == 0) ? i_image_width
                                  : i_image_width × i_image_height
```

- **line binning** 模式下，深度 = 一行宽度（合并读出为单行）
- **image** 模式下，深度 = 宽度 × 高度
- bevel / blank 像素不计入帧深度

## 时钟域概览

| 时钟域 | 频率 | 所属模块 |
|--------|------|----------|
| `i_clk` | 100 MHz | 系统时钟，`ccd_driver` 使用（分频产生 ADCCLK） |
| `adcclk_w` | ≤ 500 kHz | CCD 读出时钟，`ccd_driver` 产生，`ccd_frame_buf` 写侧使用 |
| `i_rd_clk` | ≤ 48 MHz | FX2 侧时钟，`ccd_frame_buf` 读侧 + `ccd_frame_tx` 使用 |

## 相关文档

- [ccd_driver 模块](ccd_driver.md) — CCD 时序驱动细节
- [ccd_frame_buffer 模块](ccd_frame_buffer.md) — 乒乓帧缓存细节
- [ccd_frame_tx 模块](ccd_frame_tx.md) — 帧发送细节
- [async_fifo 模块](async_fifo.md) — 通用异步 FIFO 实现

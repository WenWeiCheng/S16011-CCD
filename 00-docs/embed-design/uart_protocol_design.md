# UART 控制协议设计

## 1. 背景

CCD 相机的软硬件框架：

```
            fpc                usb
ccd 驱动板 ------- fpga 控制板 -------- 主机
```

- FPGA 控制板（XC7A35T/XC7A100T，MicroBlaze）通过 UART 与主机通信，承载全部控制命令。
- 帧图像数据经 FX2 USB（Slave FIFO）发送，**不占用 UART**。
- 驱动板上的 ADC/DAC 通过 SPI 挂接：`ad9826`（CCD ADC）、`ads1118`（温敏电阻、TEC 电压电流 ADC）、`dac8311`（TEC 输出电压）。

### 1.1 App 功能

1. 曝光控制：single / live / burst 采集，通过 timer 控制曝光时间；曝光完成后读出 CCD 数据到 DDR3 帧缓存。
2. 帧发送（`fetch`）：把缓存中的帧数据经 FX2 USB 发送给主机。
3. 监测温度、TEC 输出电压和输出电流。
4. 设置 TEC 输出电压。
5. 解析来自主机 UART 的命令，执行以上功能。

### 1.2 硬件控制契约

`ccd_controller` 为 AXI4-Lite 外设（寄存器映射见 `00-docs/verilog-design/ccd_controller_ip.md`，基地址 `0x44A00000`）。该契约由驱动层（HAL `CcdController` + app 驱动 `ccd`/`fx2`）消费，**app 逻辑层（本协议）不直接读写寄存器**，只调用 app 驱动的语义 API：

| 寄存器 | 作用 | 消费方 |
|--------|------|--------|
| `CTRL` | `[0]` exposure、`[1]` freq_sel、`[2]` mock_mode、`[4:3]` read_mode、`[11:5]` cdsclk_delay | `CcdController` (HAL) |
| `IMG_SIZE` | image_width / image_height | `CcdController` (HAL) |
| `BEVEL_BLANK` | bevel/blank 消隐参数 | `CcdController` (HAL) |
| `TRIGGER` | 写 `1` 触发帧发送 | `CcdController_TriggerFrameSend` → `Ccd_TriggerSend` |
| `STATUS` | `[8]` exception、`[15:9]` exception_cnt、`[16]` ddr3_done | `Ccd_GetException` / `Ccd_IsDdrReady` 等 |
| `FRAME_NUM`（`0x1C`） | 帧缓存可读帧数（32bit，独立寄存器） | `Ccd_GetFrameNum` |
| `INTR_EN` / `INTR_STS` | `[8]` exception、`[9]` tx_done、`[10]` frame_written（帧写入完成=读出完成）中断 | `CcdController_InterruptHandler` → `Ccd` 状态机 |

## 2. 总体设计决策

| 决策点 | 选择 | 理由 |
|--------|------|------|
| 消息编码 | 文本 / ASCII 命令 | 终端可直接调试，主机解析容易 |
| 交互模型 | 纯同步请求-响应，状态靠轮询 | 实现简单、易调试 |
| 采集语义 | 启动即返回 + 轮询完成 | 曝光是耗时操作，不阻塞命令通道 |
| 参数标识 | 字符串名字 | 可读、自描述 |
| 命令形态 | 每行一条，空格分隔字段 | 简单、`\r\n` 天然自同步 |
| 响应格式 | `OK` / `ERR <code> <message>` | 稳定错误码 + 可读消息 |
| 参数发现 | `LISTPARAMS` + `GETINFO` 两级 | 主机无需预知参数表 |
| GETINFO 格式 | 单行紧凑格式 | 固定字段位置，机器可读 |
| 字符串处理 | 双引号包裹含空格字段 | 可处理任意描述文本 |
| 波特率 | 115200 (8N1) | ASCII 协议下 9600 过慢；帧数据不占 UART，带宽充裕 |

## 3. 传输层与帧格式

**链路**：`axi_uartlite_0`，波特率 115200，8 数据位 / 无校验 / 1 停止位。

**帧格式** —— 每行一条消息，以 `\r\n` 结尾：

```
命令:   VERB arg1 arg2 ...  [\r\n]
响应:   OK <data...>\r\n         或   ERR <code> <message>\r\n
```

**词法规则**：
- 命令 verb 大写，参数按空格分隔。
- 含空格的字段（description、字符串值）用双引号包裹，内部引号用 `\"` 转义。
- 无嵌套结构、无分帧问题——单行自同步，`\r\n` 即消息边界。
- 行长度上限 256 字节；超限响应 `ERR 6 line too long`，固件缓冲溢出不破坏后续帧。
- 从机对任何收到的行都会给出响应：字段数超限（超过 4 个 token）→ `ERR 3 too many args`，空行 → `ERR 3 empty line`，未知动词 → `ERR 1 unknown verb`。主机「发一条、等一条」的策略下不会因无响应而挂起。
- 响应总是以 `OK` 或 `ERR` 开头，主机先匹配前缀再解析。

**错误码表**：

| 代码 | 含义 | 示例 |
|------|------|------|
| 1 | unknown verb | `FOO` |
| 2 | unknown param | `GETPARAM nonexistent` |
| 3 | invalid value | `SETPARAM exposure_time_us 2147483648` / `too many args`（字段数超限）/ `empty line`（空行） |
| 4 | not writable | `SETPARAM sensor_temp 25.0` |
| 5 | busy / not-now | 采集进行中再发 `ACQ` |
| 6 | line too long | 行超 256B |
| 7 | internal error | 底层驱动失败 |

## 4. Value System

每个参数在固件中由一个描述结构体定义：

| 字段 | 说明 |
|------|------|
| `name` | 字符串，如 `exposure_time_us` |
| `value_type` | `int_range` / `enum` / `float_range` / `string` / `bool` |
| `access` | `RO` / `RW` / `WO` |
| `description` | 可读文本，可含空格（双引号包裹） |
| `unit` | 可选，如 `us`、`degC`、`V` |
| `constraint` | 按 value_type 区分的约束对象 |

### 4.1 约束形态

| value_type | constraint 序列化 |
|------------|-------------------|
| `int_range` / `float_range` | `min:max:step` |
| `enum` | 逗号分隔合法值列表，如 `0,1,2` |
| `string` | 可选 `maxlen` 限制 |
| `bool` | 无约束 |

### 4.2 GETINFO 单行紧凑格式

```
OK <name> <type> <access> "<description>" <unit> <constraint>
```

示例：

```
OK exposure_time_us int_range RW "exposure time in us" us 1:2147483647:1
```

字段顺序固定，字符串字段双引号包裹，解析器按固定位置切分。

### 4.3 参数分组

参数按功能前缀组织（如 `tec_*`、`acq_*`、`frame_*`），`LISTPARAMS` 可按组过滤，方便主机组织 UI。

### 4.4 初始参数清单（可扩充）

| name | type | access | unit | constraint | 说明 |
|------|------|--------|------|------------|------|
| `exposure_time_us` | int_range | RW | us | 1:2147483647:1 | 曝光时间 |
| `read_mode` | enum | RW | — | `line_binning,image` | 读出模式；**切换后软件软复位（CTRL[12]）清空帧缓存并重锁帧长** |
| `freq_sel` | enum | RW | — | `100k,500k` | SCLK 频率 |
| `mock_mode` | bool | RW | — | — | 屏蔽 ADC 输出虚拟像素 |
| `cdsclk_delay` | int_range | RW | clk | 0:127:1 | CDSCLK 微调延时 |
| `image_width` / `image_height` | int_range | RW | px | 视传感器而定 | 图像尺寸；**写入后软件软复位（CTRL[12]）清空帧缓存并重锁帧长** |
| `bevel_left/top/right/bottom` | int_range | RW | px | 视传感器而定 | 消隐参数 |
| `blank_left/right` | int_range | RW | px | 视传感器而定 | 空白参数 |
| `tec_enable` | bool | RW | — | — | 制冷开关（adn8833 驱动，Gpio_general[0]） |
| `tec_voltage_set` | float_range | RW | V | 0:2.500:0.001 | TEC 输出电压设定（dac8311，Vref=2.5V，14-bit） |
| `sensor_temp` | float_range | RO | degC | 视传感器而定 | CCD 传感器 NTC 温度（ads1118 AIN0） |
| `environment_temp` | float_range | RO | degC | 视传感器而定 | 环境 NTC 温度（ads1118 AIN3） |
| `tec_voltage` | float_range | RO | V | 视传感器而定 | TEC 输出电压监测（ads1118 AIN1） |
| `tec_current` | float_range | RO | A | 视传感器而定 | TEC 输出电流监测（ads1118 AIN2） |
| `camera_name` | string | RW | — | maxlen 32 | 相机名 |
| `acq_state` | enum | RO | — | `idle,exposing,reading` | 采集状态（轮询用，映射驱动 CcdState；帧发送为正交维度，不体现在此） |
| `frame_num_ready` | int_range | RO | — | 0:4095:1 | 帧缓存中可读帧数（上限须与 BD `MAX_FRAMES` 同步，见 `board_config.h` `CCD_MAX_FRAMES`） |
| `frame_capacity` | int_range | RO | — | 0:4095:1 | 最大缓存帧数（= `CCD_MAX_FRAMES`，供主机查询缓存上限） |
| `exception_flag` | bool | RO | — | 0/1 | 帧异常电平标志（映射 `STATUS[8]`；DDR 域同步值） |
| `exception_cnt` | int_range | RO | — | 0:127:1 | 上电以来累计帧异常次数（映射 `STATUS[15:9]`，饱和计数，复位清零；异常帧不计入缓存） |
| `adc_gain_r/g/b` | int_range | RW | — | 0:63:1 | ad9826 三通道 PGA 增益码（G=0→1.0，G=63→6.0） |
| `adc_offset_r/g/b` | int_range | RW | — | 0:511:1 | ad9826 三通道 9-bit 偏移码（0x100 起为负偏移） |

## 5. 命令集定义

### 5.1 信息命令

```
LISTPARAMS                      → OK name1,name2,...        （可选按组过滤：LISTPARAMS tec_*）
GETINFO <name>                  → OK <name> <type> <access> "<description>" <unit> <constraint>
```

### 5.2 配置命令

```
GETPARAM <name>                 → OK <name> <value>          （value 按 type 序列化，字符串双引号包裹）
SETPARAM <name> <value>         → OK                          （成功即已生效）
```

- `SETPARAM` 通过约束校验后才执行；失败回 `ERR 3 invalid value` 并附可读说明（如实际约束范围）。
- RO 参数 `SETPARAM` 回 `ERR 4 not writable`。

### 5.3 采集命令

```
ACQ <mode> [args]               → OK                          （启动即返回）
   mode = single | live | burst <n> | fetch <n> | abort
GETPARAM acq_state              → OK acq_state <idle|exposing|reading>
GETPARAM frame_num_ready        → OK frame_num_ready <n>
GETPARAM frame_capacity         → OK frame_capacity <N>   （最大缓存帧数，= CCD_MAX_FRAMES）
GETPARAM exception_flag         → OK exception_flag <0|1>  （帧异常电平标志）
GETPARAM exception_cnt          → OK exception_cnt <n>     （累计帧异常次数，饱和计数）
```

**采集/发送语义**（`acq_state` 映射 ccd app 驱动的采集状态机 `CcdState`；曝光计时、`exposure` 位控制、DDR3 帧缓存均在 ccd app 驱动内部完成，app 逻辑只调用语义 API）：

- `ACQ single` 单帧：`Ccd_Start(1, us)` 启动曝光 → 帧读出完成写入缓存后回 `idle`（`frame_num_ready=1`，帧留在缓存中），主机随后 `fetch` 取走。发送完成与否不影响采集状态（帧发送为正交维度）。
- `ACQ live` 连续：`Ccd_Start(0, us)` 后曝光/读出持续循环（`exposing/reading` 交替），帧缓存在 DDR3 中累积，主机可随时 `fetch`；缓存满（`frame_num_ready` 达上限）时采集暂停等待排空，不丢帧。**驱动不再自动触发发送**，帧发送完全由 `fetch` 驱动。
- `ACQ burst <n>` 连采：`Ccd_Start(n, us)` 连续采集 n 帧入缓存后回 `idle`（期间不发送），再由主机 `fetch` 取走。`n` 必须能放入剩余缓存（`n ≤ MAX_FRAMES − frame_num_ready`），否则 `ERR 3 burst exceeds cache`；`single` 同理在缓存满时被拒绝。
- 三种采集模式统一走 `Ccd_Start(d, n, exposure_us)`（0→live、1→single、>1→burst），曝光时间均取 `exposure_time_us` 参数当前值（burst 首次获得显式曝光）。
- `ACQ fetch <n>` 发送：`Ccd_StartFetch(n)` 把缓存中 n 帧经 FX2 USB 发送给主机，**立即回 `OK`**（异步发送，硬件一次 TRIGGER 只发一帧，剩余帧由 TX_DONE 中断逐帧推进）。帧发送与采集状态机正交：曝光/读出期间可并发发送缓存帧，`acq_state` 不体现发送状态，主机以 `frame_num_ready` 是否回落判断发送完成。缓存不足（`n > frame_num_ready`）回 `ERR 5 insufficient frames (X ready)`。
- `ACQ abort`：`Ccd_Stop` 中止当前曝光 / 未完成的 fetch / burst，回 `idle`。
- 同一时刻只允许一种采集状态；采集进行中再发采集类 `ACQ`（`abort` 除外）回 `ERR 5 busy`；fetch 进行中重复 fetch 亦回 `ERR 5 busy`。
- 帧数据不占用 UART——由主机通过 FX2 USB 拉取。

### 5.4 控制命令

```
RESET → OK     （CCD 软复位: 先停当前采集/发送, 再写 CTRL[12]=1 总复位整条 CCD
                 流水线, 清空帧缓存并重锁帧长, 返回 idle）
```

- `RESET` 无参数。等价于图像参数变化时的软复位动作，供主机显式触发（如切换配置后重锁帧长、清空缓存）。
- 软复位前先 `Ccd_Stop`，保证软件状态与硬件一致；复位后回 `idle`，随时可再 `ACQ`。

## 6. 信息流时序示例

```
主机                                    设备
│  ACQ burst 4                          │
├────────────────────────────────────►│
│  OK                                 │
│◄────────────────────────────────────┤
│  （轮询）GETPARAM acq_state          │
│◄── OK acq_state reading ────────────┤
│  GETPARAM frame_num_ready           │
│◄── OK frame_num_ready 4 ────────────┤
│  ACQ fetch 4                        │
├────────────────────────────────────►│
│  OK                                 │
│◄────────────────────────────────────┤
│  （经 FX2 USB 拉取 4 帧数据）         │
│  （轮询）GETPARAM frame_num_ready   │
│◄── OK frame_num_ready 0 ────────────┤
└─────────────────────────────────────┘
```

## 7. 边界场景

| 场景 | 行为 |
|------|------|
| `SETPARAM exposure_time_us 2147483648` | `ERR 3 invalid value range 1:2147483647:1` |
| `SETPARAM sensor_temp 25.0` | `ERR 4 not writable` |
| `ACQ single` 期间再发 `ACQ live` | `ERR 5 busy` |
| `ACQ burst 16`（超出剩余缓存） | `ERR 3 burst exceeds cache` |
| `ACQ fetch 3`（缓存只有 1 帧） | `ERR 5 insufficient frames (1 ready)` |
| fetch 进行中再发 `ACQ fetch 2` | `ERR 5 busy` |
| `GETINFO nonexistent` | `ERR 2 unknown param` |
| 超长行 | `ERR 6 line too long` |
| 波特率/格式错误 | 主机侧超时检测 |

**鲁棒性**：
- 设备无条件响应每条合法命令（同步模型下主机不会卡死）。
- 固件启动完成（UART 就绪）后可打印一行 `READY` 供主机探测。

## 8. 固件架构划分

本协议的实现位于 `ccd_controller_software/ccd_controller_app/`，驱动层详见 `ccd_controller_driver_architecture.md`（本协议属 app 逻辑层，构建在 app 驱动层之上）。app 逻辑只依赖 app 驱动，不直接碰寄存器、不直接使用 Xilinx 驱动：

```
┌─ app 逻辑层（本协议）───────────────────────────────┐
│ 命令分发表 → 采集状态机 → 遥测循环（无 UART 字节级处理）│
├─ app 驱动层（ccd_controller_driver_architecture.md）│
│ heartbeat  key  led  fx2  adn8833  ccd  uart        │
│ ads1118  dac8311  ad9826                            │
├─ HAL / Xilinx 驱动层─────────────────────────────────│
│ CcdController（自制 IP） XSpi XGpio XTmrCtr XIntc    │
│ XUartLite                                          │
└─────────────────────────────────────────────────────┘
```

- **命令分发表**：const 数组 + 函数指针，`VERB → handler`；新命令只需加一行。
- **参数表**：const 数组，每参数一个描述结构体；新参数只需加一行。
- **UART 收发**：`uart` app 驱动（封装 XUartLite）按字节入行缓冲、`\r\n` 成行后回调；app 逻辑只处理完整命令行，用 `Uart_SendLine` 输出响应。行超限由 uart 驱动清缓冲并上报（对应 `ERR 6 line too long`）。
- **采集状态机**：`idle → exposing → reading → idle`（single，帧写入完成收尾）；live 为 `exposing/reading` 连续循环、burst 采满 n 帧后回 `idle`——均无自动发送，由主机 `fetch` 驱动发送；live/burst 的连续曝光由 `FRAME_WRITTEN` 中断（帧完整写入 DDR = 读出完成）推进，缓存满时暂停、主机 fetch 排空后由 `TX_DONE` 恢复。**帧发送（fetch）为正交维度**（`TxActive` 标志），不与采集状态机互斥：曝光/读出期间可并发发送缓存帧。
- **timer 分工**：`timer0` = 1ms 心跳（heartbeat，驱动按键消抖/遥测节拍）；`timer1` = 64-bit 级联曝光计时（支持秒级长曝光）——均在 app 驱动内部使用，app 逻辑不接触 timer。
- **SPI 共享总线**：ad9826/ads1118/dac8311 共用一条 AXI Quad SPI（3 片选），各芯片 SPI mode 不同（ad9826=mode 0、ads1118=mode 1、dac8311=mode 2），每个芯片驱动传输前用 `XSpi_SetOptions` 切换本芯片 mode，再同步 `XSpi_Transfer`（16-bit 帧）——app 逻辑只经 `Ads1118_*`/`Dac8311_*`/`Ad9826_*` 语义 API 访问。
- **fx2 驱动**：只设静态引脚电平（端点 2 写时序），PA0 监测 FX2 配置完成，作为帧发送门控。
- 中断接入顺序遵循 `xintc_tapp_example.c` 固定步骤。

## 9. 后续扩展点

- FX2 USB 固件（`03-usb-firmware/`，当前为空）与帧发送/收发的握手。
- 上位机驱动 / API（`04-driver/`，当前为空）基于本协议的封装。
- 遥测参数扩充（更多温度点、TEC 状态位）。
- 若未来需要事件推送（如帧完成自动上报），可扩展为带请求 ID 的异步响应，但不改变现有命令格式。

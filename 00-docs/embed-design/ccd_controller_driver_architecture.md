# CCD 控制器软件驱动架构设计

> 设计日期：2026-08-02
> 范围：驱动层设计（HAL + APP 芯片驱动），不包含 app 逻辑层（曝光状态机 / UART 命令解析 / 遥测循环）

## 1. 背景与目标

- 硬件：MicroBlaze standalone（无 RTOS），BD 外设含 `spi`(AXI Quad SPI, 3 片选, 16-bit)、`uart`(115200)、`iic`、**4×`gpio`**（`Gpio_general`/`Gpio_fx2fifo`/`Gpio_key`(含中断)/`Gpio_led`）、2×`timer`、`intc`、自制 IP `ccd_controller`(AXI4-Lite)。
- 驱动板：`ad9826`(CCD ADC)、`ads1118`(温敏电阻/TEC 电压电流 ADC)、`dac8311`(TEC 输出电压 DAC)，共用同一条 SPI 总线（3 片选）。
- 本次范围：**只设计驱动层**（HAL + APP 芯片驱动），不设计 app 逻辑层（曝光状态机/UART 命令解析/遥测循环）。
- 目标：分层解耦、API 语义清晰、无 RTOS 依赖、**不依赖 Xilinx 独有命名**（可移植到其它平台）。

**GPIO 分组**（`xparameters.h` 实例：`XPAR_GPIO_0`=FX2FIFO, `XPAR_GPIO_1`=GENERAL, `XPAR_GPIO_2`=KEY, `XPAR_GPIO_3`=LED）：

| 实例 | 位 | 信号 | 方向 |
|---|---|---|---|
| `Gpio_fx2fifo` | [0]`sloe_n` [1]`slrd_n` [2]`fifo_addr0` [3]`fifo_addr1` | 输出 | 固定端点 2 写时序 |
| `Gpio_fx2fifo` | [4]`PA0` | 输入 | FX2 sync 信号（高=配置完成，可作 USB 通道） |
| `Gpio_general` | [0]`adn8833_en` | 输出 | ADN8833 使能 |
| `Gpio_key` | [0]`key0` [1]`key1` | 输入 | 按键（含中断） |
| `Gpio_led` | [0]`led0` [1]`led1` | 输出 | LED |

**SPI 片选分配**（AXI Quad SPI 3 个片选）：

| 片选 | 芯片 | 用途 |
|---|---|---|
| `Spi_cs_0` | ad9826 | CCD 的 ADC |
| `Spi_cs_1` | dac8311 | TEC 输出电压 DAC |
| `Spi_cs_2` | ads1118 | 温敏电阻/TEC 电压电流 ADC |

**ads1118 输入引脚分配**（16-bit ΔΣ ADC，4 路单端输入，MUX 对 GND）：

| 引脚 | 信号 | 说明 |
|---|---|---|
| `AIN0` | `sensor_ntc` | CCD 传感器温敏电阻（NTC） |
| `AIN1` | `tec_vtec` | TEC 输出电压 |
| `AIN2` | `tec_itec` | TEC 输出电流 |
| `AIN3` | `environment_ntc` | 环境温敏电阻（NTC） |

> 对应 MUX[2:0] 单端配置：AIN0=100b, AIN1=101b, AIN2=110b, AIN3=111b（参照 datasheet §Config Register）。

## 2. 分层架构

```
┌──────────────────────────────────────────────────────────────┐
│  app 逻辑层（范围外）：曝光状态机 / 命令解析 / 遥测循环          │
├──────────────────────────────────────────────────────────────┤
│  app 驱动层                                                │
│   heartbeat  key  led  fx2  adn8833  ccd  uart              │
│   ads1118  dac8311  ad9826                                    │
│   （语义 API 为主 + raw 接口为辅）                              │
├──────────────────────────────────────────────────────────────┤
│  HAL 驱动层                                                   │
│   CcdController（自制 IP，Xilinx 风格但非 X 前缀）              │
│   XSpi  XGpio  XUartLite  XTmrCtr  XIntc（Xilinx 现成）        │
└──────────────────────────────────────────────────────────────┘
```

- **依赖方向（单向）**：app 逻辑 → app 驱动 → (XSpi | XGpio | XTmrCtr | XUartLite) / CcdController → Xilinx 驱动。
- **共享 spi 实例**：三个 SPI 芯片驱动直接持有全局共享的 `XSpi gSpi` 实例，各自管理自己的片选；SPI 传输用**同步轮询**（每帧仅 16-bit，阻塞几个 us，可接受）。
- **GPIO 按实例分组**：`Gpio_fx2fifo`/`Gpio_general`/`Gpio_key`/`Gpio_led` 各对应一个 XGpio 实例，app 驱动按分组使用。
- 整体运行模型仍为**中断 + 回调非阻塞**（timer/ccd/uart/gpio 走中断），仅 SPI 本身同步调用。

## 3. 目录结构

`ccd_controller_app/src/`：

```
src/
├── main.c                          # 初始化 + 启动 app（app 逻辑的挂载点，范围外）
├── lscript.ld
├── hal/
│   └── ccd_controller.h / ccd_controller.c    # 自制 IP 驱动
├── devices/
│   ├── heartbeat.h / heartbeat.c              # 系统心跳（timer0，1ms）
│   ├── key.h / key.c                          # 按键（Gpio_key）
│   ├── led.h / led.c                          # LED（Gpio_led）
│   ├── fx2.h / fx2.c                          # FX2 Slave FIFO 控制 + PA0 sync 监测
│   ├── adn8833.h / adn8833.c                  # ADN8833 使能（Gpio_general[0]）
│   ├── ccd.h / ccd.c                          # 曝光控制（timer1 64-bit）+ CcdController 组合
│   ├── uart.h / uart.c                        # UART 行缓冲 + 收发（XUartLite 封装）
│   ├── ads1118.h / ads1118.c
│   ├── dac8311.h / dac8311.c
│   └── ad9826.h / ad9826.c
└── include/
    └── board_config.h              # CS 号、GPIO 位映射、Vref、SPI 分频
```

- 全局共享 `XSpi gSpi;`、各 GPIO 实例 `XGpio gGpioFx2Fifo/gGpioGeneral/gGpioKey/gGpioLed`、`XTmrCtr gTimer0/gTimer1` 与各芯片驱动实例在 `main.c`（或单独 `board_hal.c`）声明/初始化。
- `board_config.h` 含：SPI 片选宏（`SPI_CS_AD9826=0 / SPI_CS_DAC8311=1 / SPI_CS_ADS1118=2`）、GPIO 位映射、ads1118 PGA/数据率/FS、**每通道 NTC 参数**（`tools/gen_ntc_table.py` 生成查表用）、DAC Vref、SPI 分频。
- 约定沿用 `02-fpga/ccd_controller_software/AGENTS.md`：Doxygen 头、`u8/u16/u32`、全局实例清零、检查 `XST_SUCCESS`、`xil_printf` 调试。

## 4. HAL 驱动设计

### 4.1 CcdController（自制 IP 驱动）

命名**不以 `X` 开头**（非 Xilinx 提供，便于跨平台移植），但 API 风格与 Xilinx 驱动一致：`Config` 查找表 + 实例 + `CfgInitialize` + `SelfTest` + `InterruptHandler`。文件 `ccd_controller.h/c`，类型 `CcdController`。

```c
/* ccd_controller.h */
typedef struct {
    u16 DeviceId;
    u32 BaseAddress;
    u32 IntrVecId;                 /* INTC 向量 */
} CcdController_Config;

typedef struct {
    CcdController_Config Config;
    u32  BaseAddress;
    u8   IsReady;
    u8   IsStarted;
    CcdController_Handler Handler; /* app 回调 */
    void *CallBackRef;
} CcdController;

/* 寄存器级：静态内联读写 + 位字段访问 */
static inline u32 CcdController_ReadReg(CcdController *p, u32 off);
static inline void CcdController_WriteReg(CcdController *p, u32 off, u32 val);

/* 初始化/自检 */
CcdController_Config *CcdController_LookupConfig(u16 DeviceId);
int  CcdController_CfgInitialize(CcdController *p, CcdController_Config *cfg, u32 addr);
int  CcdController_SelfTest(CcdController *p);

/* 配置语义 API（对照 IP 寄存器 0x00~0x08） */
void CcdController_SetImageSize(CcdController *p, u16 w, u16 h);       /* IMG_SIZE */
void CcdController_SetBevelBlank(CcdController *p, const CcdController_BevelBlank *bb); /* BEVEL_BLANK */
void CcdController_SetCdsclkDelay(CcdController *p, u8 delay);         /* CTRL[11:5] */
void CcdController_SetReadMode(CcdController *p, u8 mode);             /* CTRL[4:3] 0=line binning,1=image */
void CcdController_SetFreqSel(CcdController *p, u8 freq);              /* CTRL[1] 0=100k,1=500k */
void CcdController_SetMockMode(CcdController *p, u8 mock);             /* CTRL[2] */

/*
 * 注意 (read_mode / image_size 与帧缓存复位):
 *   帧缓存采用固定帧长度 (复位释放后锁定一次)。写 IMG_SIZE 或改变 read_mode 时,
 *   硬件不再自动复位; 需软件在写参数后显式调用 CcdController_SoftReset() (写
 *   CTRL[12]=1, 自清脉冲) 触发总复位, 清空帧缓存并重新锁定帧长度。因此切换
 *   read_mode / 设置图像尺寸前必须先 Ccd_Stop() 停止采集与发送 (协议层
 *   Apply_ReadMode / Apply_ImageSize 已处理), 写参数 + 软复位后即可采集。
 */

/* 采集控制语义 API */
int  CcdController_StartCapture(CcdController *p);  /* 检查 ddr3_done 后置 exposure=1 */
void CcdController_StopCapture(CcdController *p);   /* 清 exposure=0（下降沿启动读出） */
void CcdController_TriggerFrameSend(CcdController *p); /* 写 TRIGGER[0]=1 */
void CcdController_SoftReset(CcdController *p);     /* 写 CTRL[12]=1: 总复位整条 CCD 流水线 (帧长重锁) */

/* 状态查询 */
u32  CcdController_GetFrameNum(CcdController *p);   /* FRAME_NUM[0x1C] (32bit) */
u8   CcdController_IsDdrReady(CcdController *p);
u8   CcdController_GetException(CcdController *p);
u32  CcdController_GetExceptionCnt(CcdController *p);
u32  CcdController_GetStatus(CcdController *p);   /* STATUS 原样，调试用 */

/* 中断 */
void CcdController_SetHandler(CcdController *p, CcdController_Handler hdl, void *ref);
void CcdController_IntrEnable(CcdController *p, u8 tx_done_en,
                              u8 exception_en, u8 frame_written_en);
void CcdController_IntrDisable(CcdController *p);
void CcdController_InterruptHandler(void *ref);   /* 挂 INTC，回调 app */
```

**寄存器定义**（集中在头文件内 `#define`，对照 `ccd_controller_ip.md`）：

| 偏移 | 名称 | 位定义 |
|---|---|---|
| `0x00` CTRL | R/W | `[0]`exposure `[1]`freq_sel `[2]`mock_mode `[4:3]`read_mode `[11:5]`cdsclk_delay |
| `0x04` IMG_SIZE | R/W | `[15:0]`image_width `[31:16]`image_height |
| `0x08` BEVEL_BLANK | R/W | `[3:0]`bevel_l `[7:4]`bevel_t `[11:8]`bevel_r `[15:12]`bevel_b `[19:16]`blank_l `[23:20]`blank_r |
| `0x0C` TRIGGER | W | `[0]`tx_start |
| `0x10` STATUS | R | `[8]`exception `[15:9]`exception_cnt `[16]`ddr3_done |
| `0x14` INTR_EN | R/W | `[8]`exception_en `[9]`tx_done_en `[10]`frame_written_en |
| `0x18` INTR_STS | W1C | `[8]`exception_pending `[9]`tx_done_pending `[10]`frame_written_pending |
| `0x1C` FRAME_NUM | R | `[31:0]`frame_num（帧计数独立寄存器，支持缓存扩容） |

**实现要点**：
- `CfgInitialize` 只写 `BaseAddress/IsReady`，不预设图像参数（避免覆盖用户设定）；`SelfTest` 做寄存器 R/W 回读。
- `StartCapture` 前必须 `IsDdrReady`，否则返回 `XST_DEVICE_BUSY`。
- ISR：读 `INTR_STS` → 按 `INTR_EN` 掩码 → W1C 清除 → 回调 app（回调内只做最小处理）。
- 中断接入顺序遵循 `xintc_tapp_example.c` 固定步骤。

## 5. APP 驱动设计

### 5.1 heartbeat（系统心跳）

使用 timer0 作为 1ms 心跳源，供按键消抖、LED 闪烁、遥测采样节拍等周期任务使用。

```c
/* heartbeat.h */
typedef void (*HeartbeatHandler)(void *ref);   /* 每 1ms 回调 */

int  Heartbeat_Init(Heartbeat *d, XTmrCtr *tmr, u32 IntrVecId);
void Heartbeat_RegisterHandler(Heartbeat *d, HeartbeatHandler hdl, void *ref);
u32  Heartbeat_GetTick(Heartbeat *d);          /* 上电以来 tick 数（ms） */
void Heartbeat_InterruptHandler(void *ref);    /* timer0 ISR，挂 INTC */
```

**实现要点**：timer0 配为 auto-reload 周期计数，周期 = 时钟频率/1000；`Heartbeat_InterruptHandler` 里 `tick++` 并依次调用已注册 handler（内部最多 N 个，如 4 个）。

### 5.2 key（按键）

基于 `Gpio_key`（含中断），语义接口 + 内置消抖。

```c
/* key.h */
typedef enum { KEY_IDLE, KEY_PRESSED, KEY_RELEASED, KEY_LONG_PRESS } KeyEvent;
typedef void (*KeyHandler)(KeyEvent evt, void *ref);

int  Key_Init(Key *d, XGpio *gpio, u32 active_low_mask);  /* 高/低有效 */
void Key_RegisterHandler(Key *d, KeyHandler hdl, void *ref);
KeyState Key_GetState(Key *d);            /* 消抖后状态 */
void Key_Tick(Key *d, u32 ms);            /* 心跳周期调用，推进消抖 FSM */
void Key_InterruptHandler(void *ref);     /* GPIO 中断，置按键标志 */
```

**实现要点**：`Key_Tick` 由 heartbeat 每 1ms 调用一次；内部基于输入电平样本计数实现消抖与长按判定，满足阈值后触发事件回调（`KeyHandler`）。`Key_InterruptHandler` 只负责在 GPIO 边沿中断里置「电平有变化」标志，真正的状态判定放在 `Key_Tick` 里做，避免在中断上下文里做定时判断。

### 5.3 led（LED）

基于 `Gpio_led`。

```c
/* led.h */
int  Led_Init(Led *d, XGpio *gpio, u32 out_mask);
void Led_Set(Led *d, u8 idx, u8 on);      /* 按 idx，极性内置 */
void Led_On(Led *d, u8 idx);
void Led_Off(Led *d, u8 idx);
void Led_Toggle(Led *d, u8 idx);
```

### 5.4 fx2（FX2 Slave FIFO 控制）

基于 `Gpio_fx2fifo`。固定向端点 2 写数据：`sloe_n=1, slrd_n=1, fifo_addr0=0, fifo_addr1=0`（`FIFOADR[1:0]=00` 即端点 2）。同时监测 `PA0` 作为 sync 信号：高有效表示 FX2 已配置完毕，可作为 USB 通道传输数据。

```c
/* fx2.h */
int  Fx2_Init(Fx2 *d, XGpio *gpio);               /* 配置输出位并置默认电平 */
void Fx2_SetEndpoint(Fx2 *d, u8 ep);              /* 0=ep2, 1=ep4, 2=ep6, 3=ep8 */
u8   Fx2_IsUsbReady(Fx2 *d);                      /* 读 PA0：1=FX2 已配置 */
```

**实现要点**：
- 初始化时按需置 `sloe_n=1`（不读）、`slrd_n=1`（不读）、`FIFOADR=00`（端点 2）；写数据由 FPGA 侧 `ccd_controller.frame_tx` 时序驱动，软件只需把引脚设到正确静态电平。
- `PA0` 为输入位，由 app 逻辑轮询（或心跳节拍）读取 `Fx2_IsUsbReady`，仅在就绪后触发帧发送。

### 5.5 adn8833（TEC 电源使能）

基于 `Gpio_general[0]` 控制 ADN8833 的 `EN` 引脚。

```c
/* adn8833.h */
int  Adn8833_Init(Adn8833 *d, XGpio *gpio, u32 en_bit);  /* 默认 en_bit=0 */
void Adn8833_SetEnable(Adn8833 *d, u8 on);
u8   Adn8833_GetEnable(Adn8833 *d);
```

**实现要点**：`SetEnable` 置/清 `Gpio_general[0]`；使能时序（上电稳定、电流限制）由 app 逻辑控制，驱动只做电平操作。

### 5.6 ccd（曝光控制 + CCD 帧通路）

组合 `CcdController`（帧读出/缓存/发送）与 **timer1 64-bit 模式**（曝光时长计时）。区分 **single / live / burst** 三种采集模式；帧发送由主机 `fetch` 命令驱动（驱动不再自动发送）。

```c
/* ccd.h */
typedef enum {
    CCD_MODE_SINGLE,   /* 单次采集：曝光→读出，等 fetch 发送后回 IDLE */
    CCD_MODE_LIVE,     /* 连续采集：曝光/读出持续循环入缓存，主机随时 fetch */
    CCD_MODE_BURST,    /* 连采：采满 n 帧入缓存后回 IDLE（不发送） */
} CcdMode;

/* 互斥采集状态机。帧发送（TxActive 标志）是正交维度，可与任一状态共存，
 * 因此状态机内没有 TX 状态。 */
typedef enum { CCD_IDLE, CCD_EXPOSING, CCD_READING } CcdState;
typedef void (*CcdHandler)(CcdState st, void *ref);   /* 状态变化回调（仅采集状态） */

int  Ccd_Init(Ccd *d, CcdController *ctrl, XTmrCtr *tmr1, u32 IntrVecId);
int  Ccd_Start(Ccd *d, u32 n, u64 exposure_us);       /* n==0 live, n==1 single, n>1 burst(n) */
int  Ccd_StartFetch(Ccd *d, u32 n);                   /* 发送缓存中 n 帧（TX_DONE 逐帧推进） */
void Ccd_Stop(Ccd *d);                                /* 停止：中止曝光/fetch/burst，回 IDLE */
void Ccd_Abort(Ccd *d);                               /* 清 exposure=0 中止当前曝光 */
void Ccd_TriggerSend(Ccd *d);                         /* 手动触发帧发送到 FX2 */
u32  Ccd_GetFrameNum(Ccd *d);                         /* 帧缓存可读帧数（FRAME_NUM[0x1C]） */
u8   Ccd_IsDdrReady(Ccd *d);
u8   Ccd_GetException(Ccd *d);
u32  Ccd_GetExceptionCnt(Ccd *d);
CcdMode Ccd_GetMode(Ccd *d);
void Ccd_RegisterHandler(Ccd *d, CcdHandler hdl, void *ref);

/* 参数配置（封装 CcdController 寄存器访问；protocol 只经 Ccd_* API，不直接调用 CcdController） */
void Ccd_SetReadMode(Ccd *d, u8 mode);        /* 停止采集 → 写 read_mode → 软复位 */
void Ccd_SetImageSize(Ccd *d, u16 w, u16 h);  /* 停止采集 → 写 IMG_SIZE → 软复位 */
void Ccd_SetBevelBlank(Ccd *d, const Ccd_BevelBlank *bb);
void Ccd_SetFreqSel(Ccd *d, u8 freq);         /* CCD_FREQ_100K / CCD_FREQ_500K */
void Ccd_SetMockMode(Ccd *d, u8 mock);
void Ccd_SetCdsclkDelay(Ccd *d, u8 delay);
void Ccd_SoftReset(Ccd *d);                   /* 写 CTRL[12]=1 触发总复位 */
```

**实现要点**：
- 曝光流程：`Ccd_Start(n, us)` → 由 `n` 推导模式（0→LIVE、1→SINGLE、>1→BURST）→ `CcdController_StartCapture`（exposure=1 开始积分）+ timer1 64-bit 倒计时；到期 ISR 里 `CcdController_StopCapture`（exposure=0 下降沿启动读出）→ 状态 `CCD_READING`。三种模式统一入口，都显式传 `exposure_us`。
- **single / burst**：`Ccd_Start(1, us)` 与 `Ccd_Start(n, us)` 行为一致（single 即 burst(1)）。帧读出完成写入缓存（`FRAME_WRITTEN` 中断）即收尾回 `CCD_IDLE`（帧留在缓存中，等待主机 `fetch` 发送）。
- **live / burst 模式**：曝光→读出循环由 **`FRAME_WRITTEN` 中断**推进（一帧完整写入 DDR = 读出完成，硬件产生 `INTR[10]`）——收到中断即启动下一帧曝光；`burst` 采满 `n` 帧后回 `IDLE`。缓存满（`frame_num == CCD_MAX_FRAMES`）时置 `RdWaiting` 暂停采集（不丢帧），主机 `fetch` 排空后由 `tx_done` 回调恢复。帧异常中断中止所有激活模式（含 single）回 `IDLE`（防止丢帧后卡死在 `READING`）。
- **容量校验**：`Ccd_Start` 对 `n>=1`（含 single）统一校验 `avail + n ≤ CCD_MAX_FRAMES`，否则返回失败——缓存满时启动 single 也会被拒绝，避免硬件丢帧。
- **fetch 发送（正交）**：`Ccd_StartFetch(n)` 校验 `n ≤ frame_num` 后置 `TxActive=1` 并触发第一帧；剩余帧由 `tx_done` 中断逐帧触发（硬件 TRIGGER 在发送中会被丢弃，必须等 TX_DONE 再触发下一帧）；`TxActive` 在 `FetchPending` 归零时清除。发送期间采集状态机保持原状——曝光/读出与发送缓存帧天然并发，互不干扰。
- timer1 用 64-bit 级联模式（`XTC_CASC_MODE`）以支持秒级长曝光；曝光时长 `exposure_us` 换算为时钟周期数。
- 帧读出/缓存/发送全由 FPGA `ccd_controller` 完成，软件在 `CcdController` 回调里推进 `CcdState` 并触发 `CcdHandler`。
- `Ccd_TriggerSend` 只在 `IsDdrReady && frame_num>0` 时写 `TRIGGER`。
- `CCD_MAX_FRAMES`（`board_config.h`）为缓存容量上限，须与 BD 中 `MAX_FRAMES` 一致；主机可经 `GETPARAM frame_capacity` 查询。
- **参数配置封装**：`Ccd_SetReadMode` / `Ccd_SetImageSize` 内部先 `Ccd_Stop` 停止采集/发送，写寄存器后 `Ccd_SoftReset`（总复位，重锁帧长并清空帧缓存）；`Ccd_SetBevelBlank` / `Ccd_SetFreqSel` / `Ccd_SetMockMode` / `Ccd_SetCdsclkDelay` 为纯转发。协议层只经 `Ccd_*` API 配置 CCD，不直接调用 `CcdController_*`。

### 5.7 uart（UART 行缓冲 + 收发）

封装 `XUartLite`，为 app 逻辑提供**按行收发**的语义接口。UART 协议的命令/响应均为 `\r\n` 结尾的一行（见 `uart_protocol_design.md`），因此驱动只做字节流 ↔ 行缓冲的转换，不解析命令内容（命令解析属 app 逻辑层）。

```c
/* uart.h */
#define UART_LINE_MAX 256               /* 行长度上限，含 \r\n */

typedef void (*UartLineHandler)(const char *line, void *ref);  /* 收到完整一行回调 */
typedef void (*UartErrorHandler)(UartError err, void *ref);    /* 超长/溢出等 */

int  Uart_Init(Uart *d, XUartLite *uart, u32 IntrVecId);       /* 115200 8N1，注册 RX 中断 */
void Uart_RegisterLineHandler(Uart *d, UartLineHandler hdl, void *ref);
void Uart_RegisterErrorHandler(Uart *d, UartErrorHandler hdl, void *ref);
int  Uart_SendLine(Uart *d, const char *line);                 /* 自动补 \r\n */
int  Uart_Send(Uart *d, const char *s, u32 n);                 /* raw：不补换行 */
```

**实现要点**：
- RX 中断按字节入环形缓冲；`\r\n`（或 `\n`）成行时，从缓冲提取完整一行（不含换行符）调 `UartLineHandler`。缓冲满或行超 `UART_LINE_MAX` 时清缓冲并调 `UartErrorHandler`（对应协议 `ERR 6 line too long`）。
- 支持半行残留：换行符未到前，残留字节保留在缓冲；中断只负责积累，成行判定在中断内完成并回调。
- TX 用阻塞发送（UARTLite TX FIFO 空位检查）或中断发送，由驱动内部实现；`Uart_SendLine` 对 app 逻辑是同步写一行。
- 波特率/实例由 `main.c`（`board_hal.c`）传入，与 XUartLite 的 `CfgInitialize` 衔接；中断接入顺序遵循固定步骤。

### 5.8 ads1118（温敏电阻 / TEC 电压 / TEC 电流 ADC）

共用 `XSpi`，`cs=Spi_cs_2`（`board_config.h` 取）。

**SPI 模式**：`CPOL=0, CPHA=1`（mode 1）——SCLK 空闲为低，**上升沿移出数据（先 MSB）**，下降沿采样。三条 SPI 芯片共用同一总线，SPI mode 必须一致。**SPI mode 可运行时动态配置**：`XSpi_SetOptions(&gSpi, XSP_MASTER_OPTION | XSP_MANUAL_SSELECT_OPTION | XSP_CLK_PHASE_1_OPTION)`（CPOL=0 即默认高有效、加 `XSP_CLK_PHASE_1_OPTION` 置 CPHA=1），无需改 BD。

**运行模式**：连续转换模式（`MODE=0`），数据率 **860 SPS**，PGA 满量程 **±4.096 V**。每 **2ms** 读一次转换结果，每 **8ms** 切换一个输入通道，轮流对 4 路信号转换。

```c
/* ads1118.h */
typedef enum {
    ADS1118_MUX_SENSOR_NTC,   /* AIN0: CCD 传感器 NTC */
    ADS1118_MUX_TEC_V,        /* AIN1: TEC 输出电压 */
    ADS1118_MUX_TEC_I,        /* AIN2: TEC 输出电流 */
    ADS1118_MUX_ENV_NTC,      /* AIN3: 环境 NTC */
} Ads1118_Mux;

int  Ads1118_Init(Ads1118 *d, XSpi *spi, u8 cs);                 /* 连续模式 + 860sps + FS=±4.096V */
int  Ads1118_SetChannel(Ads1118 *d, Ads1118_Mux mux);            /* 写新 MUX 配置（连续模式即时生效） */
int  Ads1118_ReadRaw(Ads1118 *d, s16 *raw);                      /* NOP 传输取回最近一次 16-bit 结果 */
int  Ads1118_WriteConfig(Ads1118 *d, u16 cfg);                   /* raw：写配置寄存器 */
```

**实现要点**：
- 单端测量（MUX 对 GND）：`AIN0=100b, AIN1=101b, AIN2=110b, AIN3=111b`。配置寄存器字段：`SS(15) / MUX[2:0](14:12) / PGA[2:0](11:9) / MODE(8) / DR[2:0](7:5) / TS_MODE(4) / PULL_UP_EN(3) / NOP[1:0](2:1)`；连续模式 `SS=0, MODE=0`，`DR=110b`=860SPS，`PGA=000b`=FS ±4.096V。
- **`ReadConfig` 无法实现**：读回配置需 32-bit 传输（同时回读前次结果），而 AXI Quad SPI 固定 16-bit 传输长度 → 不提供读配置接口。
- **读取即写**：每笔 SPI 事务恒为 16-bit 写（写 `NOP=01b` 取数）并同步回读 16-bit 转换结果；通道切换写完整配置（`NOP=00b`）即可。
- **调度节拍**（由 app/心跳驱动）：`Ads1118_SetChannel` 每 8ms 轮换一次 mux；`Ads1118_ReadRaw` 每 2ms 调用一次取数。860SPS ≈ 1.16ms/次转换，2ms 采样与 8ms 换通道留有充足建立时间。
- 工程值换算：`V = code × (4.096 / 2^15)`（单端半量程）；NTC 温度由 app 逻辑查表换算（见下），驱动不提供语义接口。
- **NTC 温度换算**：sensor（AIN0）与 environment（AIN3）两通道**各自独立查表**，支持不同的 NTC 器件 / 分压电阻。两者分压拓扑（已确认）：`Vref─R1─(抽头)─R2─Rntc─GND`，ADC 测抽头对地电压，`V = Vref·(R2+Rntc)/(R1+R2+Rntc)`，`code = V/4.096·32768`。每通道参数（`R1/R2/R25/B/Vref`，当前为占位值）在 `board_config.h` 以 `NTC_SENSOR_*` / `NTC_ENV_*` 宏定义；`tools/gen_ntc_table.py` 据此按 B 公式生成升序 code 的 `code→tempX10` 查找表（`logic/ntc_tables.h`，GENERATED 勿手改），运行时由纯逻辑模块 `logic/ntc.c` 做线性插值（方向无关、两端钳位）。改 NTC 参数后需重跑生成脚本。
- 内部用 `XSpi_SetSlaveSelect(spi, cs)` 选片后同步 `XSpi_Transfer`（16-bit 帧）。

### 5.9 dac8311（TEC 输出电压 DAC）

共用 `XSpi`，`cs=Spi_cs_1`（`board_config.h` 取）。

**SPI 模式**：`CPOL=1, CPHA=0`（mode 2）——SCLK 空闲为高，**下降沿移出数据，上升沿采样，先 MSB**。与 ads1118（mode 1）不同，二者共用同一总线 → 每个芯片传输前需用 `XSpi_SetOptions` 切换对应 mode（见 §7）。

**帧格式**：16-bit，MSB first。`[15:14]` 控制位、`[13:0]` DAC 输入数据：

| [15:14] | 模式 | 说明 |
|---|---|---|
| `00` | Normal operation | 正常输出 `Vout` |
| `01` | Power-down | 输出阻抗 ≈ 1 kΩ |
| `10` | Power-down | 输出阻抗 ≈ 100 kΩ |
| `11` | Power-down | 输出 High-Z |

```c
/* dac8311.h */
int  Dac8311_Init(Dac8311 *d, XSpi *spi, u8 cs, float vref);
int  Dac8311_SetVoltage(Dac8311 *d, float volt);  /* 换算并写 16-bit，[15:14]=00 正常模式 */
int  Dac8311_SetRaw(Dac8311 *d, u16 code);        /* raw：code[15:14] 控制位 + code[13:0] 数据 */
int  Dac8311_SetPowerDown(Dac8311 *d, u8 pd);     /* pd: 1=1kΩ, 2=100kΩ, 3=High-Z */
```

**实现要点**：

- 帧 `[15:14]=PD1:PD0, [13:0]=D13:D0`，MSB first；`Vout = Vref × D / 2^14`，`Vref = 2.5V`（`board_config.h`）。
- `SetVoltage`：先换算 `D = volt × 2^14 / Vref`（钳位 0~16383），再与 `PD=00` 组合成 16-bit。
- 传输前切 `CPOL=1, CPHA=0`；`SetPowerDown` 直接写控制位。
- 内部用 `XSpi_SetSlaveSelect(spi, cs)` 选片后同步 `XSpi_Transfer`（16-bit 帧）。

### 5.10 ad9826（CCD 的 ADC 配置）

共用 `XSpi`，`cs=Spi_cs_0`（`board_config.h` 取）。

**SPI 模式**：`CPOL=0, CPHA=0`（mode 0）——SCLK 空闲为低，MSB first。与 ads1118（mode 1）、dac8311（mode 2）不同，传输前需切到对应 mode（见 §7）。

**帧格式**：一次读写 16-bit，MSB first：`R/Wb(15) / A[2:0](14:12) / 3'b000(11:9) / D[8:0](8:0)`。`R/Wb`：`0`=Write，`1`=Read。

**寄存器表**（地址 = `A2:A1:A0`）：

| 寄存器 | A2 | A1 | A0 | D8 | D7 | D6 | D5 | D4 | D3 | D2 | D1 | D0 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Configuration | 0 | 0 | 0 | 0 | Input Rng | VREF | 3CH Mode | CDS On | Clamp | Pwr Dn | 0 | 1 Byte Out |
| MUX Config | 0 | 0 | 1 | 0 | RGB/BGR | Red | Green | Blue | 0 | 0 | 0 | 0 |
| Red PGA | 0 | 1 | 0 | 0 | 0 | 0 | MSB | | | | | LSB |
| Green PGA | 0 | 1 | 1 | 0 | 0 | 0 | MSB | | | | | LSB |
| Blue PGA | 1 | 0 | 0 | 0 | 0 | 0 | MSB | | | | | LSB |
| Red Offset | 1 | 0 | 1 | MSB | | | | | | | | LSB |
| Green Offset | 1 | 1 | 0 | MSB | | | | | | | | LSB |
| Blue Offset | 1 | 1 | 1 | MSB | | | | | | | | LSB |

**Configuration 寄存器**（D8、D1 恒置 0）：

| D8 | D7 | D6 | D5 | D4 | D3 | D2 | D1 | D0 |
|---|---|---|---|---|---|---|---|---|
| 0 | Input Range | Internal VREF | 3CH Mode | CDS Operation | Clamp Bias | Power-Down | 0 | Output Mode |
| set to 0 | 1=4V* 0=2V | 1=Enabled* 0=Disabled | 1=On* 0=Off | 1=CDS* 0=SHA | 1=4V* 0=3V | 1=On 0=Off* | set to 0 | 0=2Byte* 1=1Byte |

\* 上电默认值。

**MUX Config 寄存器**（D8、D3:D0 恒置 0）：

| D8 | D7 | D6 | D5 | D4 | D3 | D2 | D1 | D0 |
|---|---|---|---|---|---|---|---|---|
| 0 | MUX Order | Channel Select | Channel Select | Channel Select | 0 | 0 | 0 | 0 |
| | 1=R-G-B* 0=B-G-R | 1=RED 0=Off* | 1=GREEN 0=Off* | 1=BLUE 0=Off* | set to 0 | set to 0 | set to 0 | set to 0 |

**PGA 增益**：Gain[5:0]（D5:D0，D8:D6=000），`Gain = 6.0 / (1 + 5.0 × (63−G)/63)`，G=0→1.0、G=63→6.0。

**Offset 偏移**：Offset[8:0]，9-bit 有符号；0 步进，`+300 mV`（0x17F）、`−300 mV`（0x100）。

```c
/* ad9826.h */
typedef struct {
    u8 Config;      /* Configuration 寄存器（D8=0, D7 input range, D6 vref, D5 3ch, D4 CDS, D3 clamp, D0 1byte） */
    u8 Mux;         /* MUX Config（D7 RGB/BGR, D6 Red, D5 Green, D4 Blue） */
    u8 GainR, GainG, GainB;   /* 各通道 PGA 增益码（0~63） */
    u16 OffR, OffG, OffB;     /* 各通道偏移码（9-bit 有符号，协议暴露 0:511） */
} Ad9826_Config;

int  Ad9826_Init(Ad9826 *d, XSpi *spi, u8 cs);
int  Ad9826_Configure(Ad9826 *d, const Ad9826_Config *cfg); /* 依序写各寄存器 */
int  Ad9826_WriteReg(Ad9826 *d, u8 addr, u16 val);          /* raw：R/Wb=0 */
int  Ad9826_ReadReg(Ad9826 *d, u8 addr, u16 *val);          /* raw：R/Wb=1 */
```

**实现要点**：
- 帧装配：`u16 word = (rw << 15) | (addr << 12) | (data & 0x1FF)`；写 `rw=0`，读 `rw=1`。
- **可读可写**（R/Wb 首位控制），`ReadReg` 供校验/调试；`Configure` 用默认值补齐未指定字段。
- 传输前切 `CPOL=0, CPHA=0`；内部用 `XSpi_SetSlaveSelect(spi, cs)` 选片后同步 `XSpi_Transfer`（16-bit 帧，正好容纳完整帧）。

## 6. 中断与运行模型

- 驱动统一非阻塞 + 回调；超循环 `main` 轮询事件标志，耗时操作在回调/状态机中推进。
- **SPI 除外**：芯片驱动内部同步轮询 `XSpi_Transfer`（短传输，主循环短暂阻塞）。
- INTC 中断源（`xparameters.h`）与接入者：

| 向量 | 外设 | ISR |
|---|---|---|
| 0 | `ccd_controller` | `CcdController_InterruptHandler` → 内部转 `Ccd` 状态机（frame_written 推进采集环 / tx_done 推进 fetch / exception 中止） |
| 1 | `timer0` | `Heartbeat_InterruptHandler`（1ms 心跳，驱动 Key_Tick 等） |
| 2 | `spi` | （未用，SPI 同步轮询） |
| 3 | `uart` | `Uart_InterruptHandler`（按字节入缓冲，成行回调） |
| 4 | `iic` | IIC ISR |
| 5 | `timer1` | timer1 ISR → `Ccd` 曝光到期回调 |
| 6 | `Gpio_key` | `Key_InterruptHandler` |

- 各 ISR 只做最小处理，经回调 + volatile 标志与主循环通信。

## 7. 实现要点与待确认项

1. **SPI 位宽**：AXI Quad SPI 配 `NUM_TRANSFER_BITS=16`；三个芯片均为 16-bit 帧（ads1118 16-bit、dac8311 16-bit、ad9826 16-bit 含 R/W+addr+data），无需额外位宽处理。
2. **SPI 模式（按芯片切换）**：三个芯片 SPI mode 不一致——ads1118 需 `CPOL=0, CPHA=1`（mode 1，`XSP_CLK_PHASE_1_OPTION`），dac8311 需 `CPOL=1, CPHA=0`（mode 2，`XSP_CLK_ACTIVE_LOW_OPTION`），ad9826 需 `CPOL=0, CPHA=0`（mode 0，默认）。共用一条总线 → **每个芯片驱动在发起传输前**用 `XSpi_SetOptions` 切到自己的 mode，切完再 `XSpi_Transfer`。
3. **DDR3 就绪门控**：`CcdController_StartCapture` 返回前检查 `STATUS[16]`。
4. **DAC8311 帧长**：dac8311=14-bit(16-bit 帧)
5. **范围约束**：不实现 app 逻辑（曝光/命令/遥测），只建驱动与挂载点。
6. **timer 分配**：timer0=心跳(1ms)，timer1=CCD 曝光计时（64-bit 级联支持长曝光），需确认 timer1 级联后中断向量仍为 `XPAR_INTC_0_TMRCTR_1_VEC_ID`。
7. **FX2 时序**：`fx2` 驱动只设静态引脚电平，实际 `FLAGA/FLAGB/FIFO 读写时序` 由 FPGA `frame_tx` 完成，软件不参与时序。
8. **ads1118 调度**：连续模式 860SPS；`SetChannel` 每 8ms 轮换 mux，`ReadRaw` 每 2ms 取数——节拍由 app/心跳驱动，驱动本身只提供原语。


# AGENTS.md

本目录是 `ccd_controller_software/`，Vitis（2020.x）工作区，MicroBlaze standalone 软件工程。约定开发、构建、硬件同步与 git 提交事项。

## 工作区结构

```
ccd_controller_software/
├── mb_subsystem/              平台工程（基于 Vivado 导出的 .xsa 生成）
│   ├── platform.spr           平台描述（handoff 指向 hw/mb_subsystem_wrapper.xsa，勿手改）
│   ├── hw/                    硬件副本（.xsa/.bit 被忽略，.mmi 未忽略）
│   ├── bitstream/ tempdsa/    位流缓存（.bit 被忽略）
│   ├── export/mb_subsystem/   导出平台 (.xpfm/.spfm，生成物)
│   └── microblaze_0/standalone_domain/bsp/   BSP（生成物，勿手改）
├── test/                      主应用工程（源码在 src/）
│   ├── test.prj               工程定义（runtime=C/C++, cpu=standalone_domain）
│   └── src/                   唯一需要维护的应用源码
│       ├── testperiph.c       main 入口（目前跑 Intc 自测 + 中断配置）
│       ├── xgpio_tapp_example.c / xintc_tapp_example.c   外设自测示例
│       ├── gpio_header.h / intc_header.h
│       └── lscript.ld         链接脚本（LMB/BRAM 内存布局）
├── test_system/               主系统工程（关联平台+应用，构建/烧录入口）
├── perph_test/                残留空壳（只剩 .project，勿用；已被 test/ 取代）
└── *_example_1/ + *_example_1_system/   Xilinx 驱动示例工程（参考用）
    ├── xgpio_example_1        GPIO 示例
    ├── xintc_example_1        中断控制器示例
    ├── xspi_intr_example_1    SPI 中断示例
    ├── xtmrctr_intr_64bit_example_1 / xtmrctr_intr_example_1   定时器示例
    └── xuartlite_intr_example_1    UART 中断示例
```

## 应用开发约定

- 调试输出走 UART stdout：`axi_uartlite_0`，**波特率 115200**（BD 中 C_BAUDRATE=115200），用 `xil_printf` / `print`。
- 沿用现有模板模式：每个外设一个自测文件（如 `xgpio_tapp_example.c`）+ 同名 header 声明函数，在 `testperiph.c` 的 main 中按需调用。
- BSP 是生成物，不要手改；standalone 的 stdin/stdout 等选项在 BSP 设置里配置，改后 Regenerate BSP。
- 改硬件（BD / IP / 约束）后，软件侧按上文重新同步再联调。

## 外设使用参考

本设计 BD 内可用外设及对应软件宏（见 BSP `xparameters.h`）。驱动源码在 BSP 的 `mb_subsystem/microblaze_0/standalone_domain/bsp/microblaze_0/libsrc`（如 `gpio_v4_6`、`intc_v3_11`、`spi_v4_6`、`tmrctr_v4_6`、`uartlite_v3_4`），API 统一为 `X<Periph>_<动词>` 命名，头文件 `x<periph>.h`。

| 外设 (BD 实例) | Device ID 宏 | 中断 Vec ID 宏 | 参考示例（仓库内源码） |
|---|---|---|---|
| GPIO (`axi_gpio_0`) | `XPAR_AXI_GPIO_0_DEVICE_ID`（别名 `XPAR_GPIO_0_DEVICE_ID`） | `XPAR_INTC_0_GPIO_0_VEC_ID` | `xgpio_example_1/src/xgpio_example.c`（LED 闪烁/双通道）、`test/src/xgpio_tapp_example.c`（输出+输入自测） |
| Intc (`microblaze_0_axi_intc`) | `XPAR_MICROBLAZE_0_AXI_INTC_DEVICE_ID`（别名 `XPAR_INTC_0_DEVICE_ID`） | — | `xintc_example_1/src/xintc_example.c`、`test/src/xintc_tapp_example.c`（中断系统搭建） |
| SPI (`axi_quad_spi_0`) | `XPAR_SPI_0_DEVICE_ID` | `XPAR_INTC_0_SPI_0_VEC_ID` | `xspi_intr_example_1/src/xspi_intr_example.c`（主模式/回环/中断） |
| 定时器 (`axi_timer_0` / `axi_timer_1`) | `XPAR_TMRCTR_0_DEVICE_ID` / `XPAR_TMRCTR_1_DEVICE_ID` | `XPAR_INTC_0_TMRCTR_0_VEC_ID` / `_1_` | `xtmrctr_intr_example_1/src/xtmrctr_intr_example.c`（32 位周期中断）、`xtmrctr_intr_64bit_example_1/src/xtmrctr_intr_64bit_example.c`（级联 64 位） |
| UART (`axi_uartlite_0`) | `XPAR_UARTLITE_0_DEVICE_ID` | `XPAR_INTC_0_UARTLITE_0_VEC_ID` | `xuartlite_intr_example_1/src/xuartlite_intr_example.c`（中断收发回环） |

另有 `axi_iic_0`（`XPAR_IIC_0_DEVICE_ID`，`XPAR_INTC_0_IIC_0_VEC_ID`），仓库内暂无示例，驱动 API 见 BSP `xiic.h`。

- 示例源码中的 `DEVICE_ID` / `VEC_ID` 宏都映射自 xparameters.h；本设计已提供 `XPAR_GPIO_0_DEVICE_ID`、`XPAR_INTC_0_DEVICE_ID`、`XPAR_SPI_0_DEVICE_ID`、`XPAR_TMRCTR_0_DEVICE_ID`、`XPAR_UARTLITE_0_DEVICE_ID` 等别名，Xilinx 原版示例常量常可直接使用。
- `*_example_1` 工程仅作参考（各自带独立 `*_system` 工程，不进 `test_system`）。要实际跑某外设，把对应函数以 `TESTAPP_GEN` 模式搬进 `test/src` 并在 `testperiph.c` 中调用。

### API 风格

- 简单外设（GPIO/Intc/UartLite/TmrCtr）：`X<Periph>_Initialize(&Instance, DeviceId)`，随后一般跟 `X<Periph>_SelfTest(&Instance)` 自检；**SPI 例外**——新版驱动用 `XSpi_LookupConfig` + `XSpi_CfgInitialize`（`XSpi_Initialize` 已废弃）。
- 带中断的外设接入 Intc 的顺序固定（见各例的 `*SetupIntrSystem` 与 `test/src/xintc_tapp_example.c`）：
  1. `XIntc_Initialize(&Intc, INTC_DEVICE_ID)`
  2. `XIntc_Connect(&Intc, VEC_ID, (XInterruptHandler)X<Periph>_InterruptHandler, (void *)&Instance)` —— 驱动自带 ISR 一律叫 `X<Periph>_InterruptHandler`
  3. `XIntc_Start(&Intc, XIN_REAL_MODE)`
  4. `XIntc_Enable(&Intc, VEC_ID)`
  5. 一次性：`Xil_ExceptionInit()` → `Xil_ExceptionRegisterHandler(XIL_EXCEPTION_ID_INT, (Xil_ExceptionHandler)XIntc_InterruptHandler, &Intc)` → `Xil_ExceptionEnable()`
- 回调经 `X<Periph>_Set<类型>Handler(&Instance, MyHandler, CallBackRef)` 注册（如 `XTmrCtr_SetHandler`、`XSpi_SetStatusHandler`、`XUartLite_SetSendHandler`/`_SetRecvHandler`）。回调内只做最小处理，通过 `volatile` 全局变量与主线程通信，避免死等。
- 数据类型用 `u8/u16/u32`（`xil_types.h`），不用 int 表示位宽；每个 API 返回值都检查是否 `XST_SUCCESS`。
- 调试打印用 `xil_printf`（示例常 `#define printf xil_printf` 缩小固件体积）；`xil_printf` 的 `%x` 等变参需把 u32 显式强转（如 `(int)`）。

### 注释与文件风格

- 文件头为 Doxygen 风格 `/** @file ... @note <pre> MODIFICATION HISTORY: ... </pre>`；每个函数前用 `/**/` 块注释写明 `@param` / `@return` / `@note`；每段关键 API 前加解释性 `/* ... */` 注释。新代码沿用。
- 驱动实例声明为全局（清零、方便调试器查看）。

## 构建与调试

- 常规流程：Vitis IDE 打开本工作区 → 构建 `test_system` → Run / Debug。
- `test/Debug/makefile` 是 IDE 生成的（每次构建会重写），不要手编。
- UART 打印对不上时，硬件波形问题回 `ccd_controller_hardware` 用 ILA 抓（约束见其 `vivado_proj/.../constrs_1/new/debug.xdc`）。

## Git 提交约定

- **整个目录当前未被 git 追踪**（未提交，不是被 ignore）。
- 不要盲目 `git add` 整个目录 —— 会把数百个 BSP/平台生成文件一起带入（`mb_subsystem/export/`、`bsp/` 等）。只提交源码与工程定义：
  - `test/src/*`、`test/test.prj`
  - `test_system/test_system.sprj`
  - `mb_subsystem/platform.spr`
  - 如需提交驱动示例，同理只带 `*_example_1/src/*` 与其 `.prj`、`*_example_1_system/*.sprj`。
- 根 .gitignore 只按模式忽略 `.xsa` / `.bit` / `*.log` / `.metadata/` / `.sdk/` / `.project` / `.cproject` / `Debug/` 等；**`*.mmi`、`export/`、`hw/`、`tempdsa/`、`bsp/` 并未被忽略**，仍以未追踪文件形式出现在 `git status`（当前约 500+ 个）。
- `.analytics/`、`RemoteSystemsTempFiles/`、`mb_subsystem/.log/` 也未被 gitignore —— 提交前留意不要把它们一起 add。

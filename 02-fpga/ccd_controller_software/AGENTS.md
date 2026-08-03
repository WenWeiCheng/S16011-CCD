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
- 使用英文

## 构建与调试

- 常规流程：Vitis IDE 打开本工作区 → 构建 `test_system` → Run / Debug。
- `test/Debug/makefile` 是 IDE 生成的（每次构建会重写），不要手编。
- UART 打印对不上时，硬件波形问题回 `ccd_controller_hardware` 用 ILA 抓（约束见其 `vivado_proj/.../constrs_1/new/debug.xdc`）。

### 无头构建（mb-gcc 命令行）经验

- `xsct app build -name ccd_controller_app` 在本工作区会报 **`Invalid Workspace`**（SDK 后端问题：`platform list` / `app list` 都正常，唯独 build 失败）。命令行走不通时用**手工 mb-gcc 构建**验证编译，正式烧录仍回 Vitis IDE。
- 工具链：`C:\Xilinx\Vitis\2020.1\gnu\microblaze\nt\bin\mb-gcc.exe`（GCC 9.2.0）。编译/链接标志从示例工程 `*_example_1/Debug/{makefile,src/subdir.mk,objects.mk}` 抄。
- 编译（每个 .c）：
  ```
  mb-gcc -O2 -g0 -c -mlittle-endian -mcpu=v11.0 -mxl-soft-mul -ffunction-sections -fdata-sections \
         -I<export>/sw/mb_subsystem/standalone_domain/bspinclude/include -I<src根> -o out.o <源文件>
  ```
  把 `main.c` 拷到临时目录再编会让相对 include（`"hal/board_hal.h"`）失效，必须补 `-I<src根>`。
- 链接：
  ```
  mb-gcc -Wl,-T -Wl,<lscript.ld> -L<export>/.../standalone_domain/bsplib/lib \
         -mlittle-endian -mcpu=v11.0 -mxl-soft-mul -Wl,--no-relax -Wl,--gc-sections \
         -o app.elf <objs...> -Wl,--start-group,-lxil,-lgcc,-lc,--end-group
  ```
  `_start` / 向量表来自 libxil（standalone BSP 的 crt0），无需额外对象；`main` 必须存在（crt0 引用）。
- 开了 FPU 后 BSP 重建会自动加 `-mxl-hard-float`，源码无需改；未开 FPU 时 float 走软浮点（默认 `-mxl-soft-mul`），也不用改。

#### newlib printf/strtod 体积教训（重要）

- **不要用 newlib `snprintf` / `sprintf` / `strtof`**。newlib 的 `snprintf` 只要被调用（哪怕只格式化 `%d/%s`），就会把**完整浮点 printf 引擎**链进固件：`_svfprintf_r` ~12KB + `_svfiprintf_r` 5.5KB + `_dtoa_r` 7KB + malloc/realloc/free 机制 4.5KB + `__udivdi3/__umoddi3` 5.4KB；`strtof` 再拉 `_strtod_l` 7KB + 转换辅助 ~6KB，合计 ~40+KB。实测带 snprintf+strtof 的协议固件 **155KB > 128KB** local mem，直接链接溢出。
- `xil_printf` **不支持 %f**，且与是否开 FPU 无关（它是轻量实现，没写浮点；FPU 只加速运算）。
- 对策：**数字格式化/解析全部手写**（见 `ccd_controller_app/src/app_logic/proto_num.c`：itoa / 定点小数 / 十进制浮点解析）；`strlen/strcmp/memcpy` 等叶子函数可放心用（极小，基线已引用）。协议响应串用手写拼接器。
- 体积基线：原驱动层（纯 xil_printf）≈62KB total（text 29.5K + data 0.5K + bss 33K，bss 含 16K heap + 16K stack）；全手写协议后 `-O2` ≈85KB / `-O0`(Debug) ≈92KB，128KB 放得下。

#### 内存布局

- 128KB local mem 在 `lscript.ld` 对应 `ORIGIN = 0x50, LENGTH = 0x1FFB0`（合计 0x20000 = 128KiB），栈/堆各 `0x4000`（16KB）。改 BD 的 local mem 大小后 Vitis 会重生成该文件，确认尺寸不回退。

#### 构建脚本（Windows PowerShell）注意事项

- PowerShell 5.1 解析**无 BOM 的 UTF-8 脚本遇到中文注释会报语法错**——写 .ps1 脚本避免中文字符，或保存为带 BOM 的 UTF-8。
- 给 mb-gcc 传参用**参数数组 + splat**（`& $MBGCC @args`）最稳；`ForEach-Object` 块内给 gcc 传数组参数曾出过 `.0: No such file` 之类的解析问题，两种已验证可用的写法：单个 CFLAGS 字符串、或循环外先组好数组再 splat。
- 体积/符号分析：`mb-nm --size-sort -S app.elf` 看最大符号；`mb-nm app.elf | Select-String "符号"` 确认没链进 newlib printf/malloc（`_svfprintf_r/_dtoa_r/_strtod_l/_malloc_r`）；`mb-size app.elf` 看各段。

#### 纯逻辑模块可主机单测

- 与硬件无关的纯逻辑（解析/格式化）抽成无 Xilinx 依赖的模块（如 `app_logic/proto_num.c`，只用 `xil_types.h` 的类型），临时目录放一个 `xil_types.h` 桩即可用主机 gcc 直接编译跑单测，无需硬件、迭代快。曾在单测中发现并修复两处逻辑 bug（约束解析遇 `:` 失败、Utoa/Itoa 未 NUL 结尾）。

### clangd / compile_commands.json 经验

- Vitis 工程（Eclipse CDT + GNU Make）的编译命令不在顶层 `makefile`，而在 `Debug/` 下由 `makefile` + 各 `subdir.mk` 拼出（`mb-gcc -c ...`）。
- 生成 `compile_commands.json` 用 Python 工具 **compiledb**（`pip install compiledb`；Windows 上 bear 不可用）。已验证命令（在 `Debug/` 目录下执行）：
  ```
  make -n -B all 2>&1 | compiledb -f -o ..\compile_commands.json
  ```
  - `-B`（always-make）强制所有目标视为过期，保证干跑打印全部编译命令；`-n` 只打印不执行，无需 mb-gcc 在 PATH。
  - **坑**：`compiledb -n make -B`（compiledb 自带 no-build 子进程模式）在 Windows + GnuWin32 make 下只捕获 1 条命令；必须用「make 输出管道喂给 compiledb 从 stdin 解析」的方式。
  - 产物放应用工程根（如 `ccd_controller_app/compile_commands.json`），clangd / C/C++ 插件会自动向上查找；改了 `subdir.mk`（增删源文件）或 BSP 路径后重跑即可。
- clangd 报错修复（在应用工程根放 `.clangd`，参考 `ccd_controller_app/.clangd`）：
  - `drv_unknown_argument: '-mxl-soft-mul'`：clang 不认识 mb-gcc 专有参数（`-mxl-*`、`-mcpu=v11.0`、`-mlittle-endian`、`-Wl,*`、`-MT/-MF/-MMD/-MP` 等），用 `CompileFlags.Remove` 过滤（不影响真实编译）。
  - `pp_file_not_found: 'xpseudo_asm.h'`：**不是缺文件**，而是缺预定义宏。`xil_io.h` 里 `#if defined(__MICROBLAZE__)` 决定 include `mb_interface.h`（MicroBlaze 有）还是 `xpseudo_asm.h`（仅 ARM 平台有）；clang 不自动定义 `__MICROBLAZE__`，走错分支。用 `CompileFlags.Add: -D__MICROBLAZE__`（必要时加 `-D__microblaze__`）修复。
  - 改完 `.clangd` 需重启 clangd（命令面板 "clangd: Restart language server"）才生效。

## Git 提交约定

- **整个目录当前未被 git 追踪**（未提交，不是被 ignore）。
- 不要盲目 `git add` 整个目录 —— 会把数百个 BSP/平台生成文件一起带入（`mb_subsystem/export/`、`bsp/` 等）。只提交源码与工程定义：
  - `test/src/*`、`test/test.prj`
  - `test_system/test_system.sprj`
  - `mb_subsystem/platform.spr`
  - 如需提交驱动示例，同理只带 `*_example_1/src/*` 与其 `.prj`、`*_example_1_system/*.sprj`。
- 根 .gitignore 只按模式忽略 `.xsa` / `.bit` / `*.log` / `.metadata/` / `.sdk/` / `.project` / `.cproject` / `Debug/` 等；**`*.mmi`、`export/`、`hw/`、`tempdsa/`、`bsp/` 并未被忽略**，仍以未追踪文件形式出现在 `git status`（当前约 500+ 个）。
- `.analytics/`、`RemoteSystemsTempFiles/`、`mb_subsystem/.log/` 也未被 gitignore —— 提交前留意不要把它们一起 add。

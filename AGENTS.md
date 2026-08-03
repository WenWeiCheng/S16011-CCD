# AGENTS.md

## 仓库简介
CCD 驱动的软硬件项目。目录结构如下（`00-docs/` 与 `datasheets/` 已被 gitignore，不入库）：

```
00-docs/                 设计笔记 / 规格书（gitignore）
01-pcb/                  PCB 设计文件（含 BOM.xlsx、old-driver/ 参考文件）
02-fpga/
  ├── ccd_controller_hardware/   Vivado 工程（RTL/TB/IP/约束）
  └── ccd_controller_software/   Vitis 工程（MicroBlaze 软件）
03-usb-firmware/         预留 — FX2 EZ-USB 固件（当前为空）
04-driver/               预留 — 上位机相机驱动 / API（当前为空）
30_Resources/            Xilinx FPGA 参考资料
nir-proj-reference/      被 gitignore 的先前 NIR 项目 Obsidian 仓库（仅作参考）
```

## FPGA 硬件子项目（Vivado）

实验基于 Xilinx XC7A100T 开发板，最终成品基于 Xilinx XC7A35T 自制控制板。

- 修改 `ccd_controller_hardware/` 下的 RTL / TB / 目录结构前，**必读** `02-fpga/ccd_controller_hardware/AGENTS.md`（含 Verilog 编码规范、TB 约定、iverilog 验证流程）。
- **Vivado 生成的 BD / IP 文件已纳入 git 追踪**（如 `vivado_proj/.../mb_subsystem.bd`、`ip/*`、`.dcp`、sim netlist 等）。在 Vivado 中改动块设计或重新生成 IP 会改动大量已追踪文件，`git status` 出现上百行改动属正常现象，不要据此误判工作区损坏。
- 顶层管脚/时钟约束在 `vivado_proj/ccd_controller_hardware.srcs/constrs_1/new/`（`port.xdc`、`clock.xdc`、`debug.xdc`）。
- `.xsa` / `.bit` / `.ltx` 等构建产物被 gitignore，不提交（可由 Vivado 重建）。

## FPGA 软件子项目（Vitis）

- `ccd_controller_software/` 是 Vitis 工作区：平台工程 `mb_subsystem/`、应用工程 `perph_test/`（源码在 `perph_test/src/`）、系统工程 `perph_test_system/`。
- 软件为 MicroBlaze standalone BSP 的 C 代码，使用 Xilinx 驱动库（XGpio、XIntc 等），经 UART stdout 输出调试。

## 含中文字符的文件名

`01-pcb/old-driver/` 及部分 `datasheets/` 文件使用 GBK 编码的中文文件名。PowerShell `dir` 会显示为乱码 — 请使用 `git ls-files` 或 Read 工具查看真实名称。**请勿重命名它们**，因为 BOM 和现有笔记中已有引用。

## 工作流程约定

- git commit 使用中文
- 如需修改 FPGA 子项目的 RTL / TB / 目录结构，请优先参考该子项目的 AGENTS.md

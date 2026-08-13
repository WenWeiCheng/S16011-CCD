# AGENTS.md

设计笔记 / 规格书目录。整目录被 `.gitignore` 忽略，不入库、无 git diff，改动无需 commit。

## 目录结构

```
00-docs/
├── AGENTS.md
├── datasheets/                    芯片数据手册 / 第三方参考源码（只读，勿修改）
│   ├── ADC/  CCD/  DAC/  Driver/  Power/  USB/
│   ├── Cypress-EZ-USB/            FX2LP 手册 + AN61345 Slave FIFO 示例源码
│   └── device-notes.xlsx
├── embed-design/                  嵌入式软件设计文档
│   ├── ccd_controller_driver_architecture.md   HAL + 芯片驱动架构
│   └── uart_protocol_design.md                UART 协议
└── verilog-design/                FPGA RTL 模块设计文档
    ├── .assets/                   文档插图
    ├── ccd.md                     ↔ rtl/ccd.v（顶层，含子模块总表）
    ├── ccd_driver.md              ↔ rtl/ccd_driver.v
    ├── ccd_frame_buffer_fifo.md   ↔ rtl/ccd_frame_buf.v（FIFO 实现）
    ├── ccd_frame_buffer_ddr.md    ↔ rtl/ccd_frame_buf.v（DDR 实现）
    ├── ccd_frame_tx.md            ↔ rtl/ccd_frame_tx.v
    ├── ccd_controller_ip.md       ↔ AXI4-Lite 封装（寄存器映射，软件访问规范来源）
    ├── ccd-state-machine.json     机器可读状态机规格
    ├── ccd-timing.json            机器可读时序规格
    └── statemachine/              *.agx（draw.io 源）+ 同名 *.png 导出
```

各模块文档与 `02-fpga/ccd_controller_hardware/rtl/` 同名模块一一对应；`embed-design/` 对应 `02-fpga/ccd_controller_software/`。

## 规范

- 中文书写，UTF-8（无 BOM）。
- Markdown 文档命名用 `_` 分隔
- OpenCode Agent：终端（PowerShell）显示中文可能乱码 — 用 Read 工具读取。


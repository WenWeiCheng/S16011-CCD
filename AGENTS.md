# AGENTS.md

## 仓库简介
CCD 驱动的软硬件项目，刚开始启步。规划、建立起来的目录结构如下（有些目录尚为空）：

```
00-docs/                预留— 设计笔记 / 规格书
01-pcb/                 PCB 设计文件
02-fpga/                Xilinx Vivado 和 Vitis 项目
03-usb-firmware/        FX2 EZ-USB 固件
04-driver/              上位机相机驱动 / API
nir-proj-reference/     被 gitignore 的先前 NIR 项目 Obsidian 仓库（仅作参考）
```

## 含中文字符的文件名
`01-pcb/old-driver/` 及部分 `datasheets/` 文件使用 GBK 编码的中文文件名。PowerShell `dir` 会显示为乱码 — 请使用 `git ls-files` 或 Read 工具查看真实名称。**请勿重命名它们**，因为 BOM 和现有笔记中已有引用。

## 工作流程约定
- git commit 使用中文
- 如需修改 FPGA 子项目的 RTL / TB / 目录结构，请优先参考该子项目的 AGENTS.md

# AGENTS.md

## What this repo is
Scaffolding-stage multi-domain CCD controller project. Four subprojects share the root

```
00-docs/                reserved (empty) — design notes / specs
01-pcb/                 PCB design files (Kicad project not yet created)
01-pcb/old-driver/      previous-generation driver board (Altium .eprj + PDF)
01-pcb/BOM.xlsx         current board BOM
01-pcb/datasheets/      vendor PDFs (ADC, CCD, USB, gate drivers, TEC PMIC)
02-fpga/                Xilinx Vivado 2023.2 project — only real source tree
03-usb-firmware/        reserved (empty)
04-driver/              host-side camera driver / API — reserved (empty)
nir-proj-reference/     gitignored Obsidian vault from a prior NIR project (reference only)
```

Do not create files in the empty subprojects without first checking with the user; they are intentional placeholders.

## Filenames with Chinese characters
`01-pcb/old-driver/` and some `datasheets/` files have GBK-encoded Chinese names. PowerShell `dir` shows them as mojibake — use `git ls-files` or the Read tool to see real names. Do not rename them; they are referenced from the BOM and existing notes.

## Workflow expectations
- commit git in Chinese

本目录是 FPGA 子项目的 Vivado 工程根。本 AGENTS.md 约定**子项目结构**、**Verilog 编码风格**和 **testbench 写法**,所有在该目录下生成的 `.v` / `.xdc` / TB 文件必须遵守。

---

## 1. 目录结构

```
02-fpga/ccd_controller_hardware/
├── AGENTS.md                                          # 本文件 (子项目约定)
├── scripts/
│   └── bd.tcl                                          # ★ 唯一设计源：完整 BD 重建脚本 (Vivado 2020.1 导出)
├── constraint/
│   ├── BX72_core_ddr3_pin.ucf                         # DDR3 管脚参考
│   ├── port.xdc                                       # 顶层管脚约束
│   ├── clock.xdc                                      # 时钟约束 (MIG / clk_wiz 层次引用)
│   └── debug.xdc                                      # ILA 调试约束
├── ip/
│   └── ccd_controller/                                # 自定义 CCD 控制器 AXI IP (IP 仓库形态)
│       ├── ccd_controller.xpr                         #   IP 工程文件
│       └── ccd_controller.srcs/
│           ├── src/                                   #   RTL 源码 (ccd_controller_v1_0*, ccd_driver, ...)
│           │   └── test_*.v                           #     TB (与 RTL 同目录存放)
│           ├── constrs_1/new/                         #   IP 内部约束 (ccd_top.xdc, ccd_clock_ooc.xdc)
│           ├── component.xml                          #   IP 打包文件
│           └── sources_1/ip/                          #   嵌套 IP (mig_7series_0, rd/wr_ddr3_fifo)
└── vivado_proj/                                       # ⚠️ gitignore，不入库
                                                        #    由 bd.tcl + constraint/ + ip/ 重建
```

> **vivado_proj/ 不入库**：整个 Vivado 工程（`.xpr`、BD 生成物、`.dcp`、`.xsa`、`.bit` 等）均按需重建，`git status` 不应出现其中内容。
> **BD 由 `scripts/bd.tcl` 重建**：该脚本自包含 MIG 配置（运行时生成 `mig_a.prj`），不依赖任何外部文件。
> **RTL 与 TB 名字成对**:`ccd_driver.v` ↔ `test_ccd_driver.v`,均位于 `ip/ccd_controller/ccd_controller.srcs/src/`。

---

## 2. 语言与工具链

- **使用 Verilog**,不使用 SystemVerilog
- 用 **iverilog** 验证语法（RTL + TB 均在 `ip/ccd_controller/ccd_controller.srcs/src/`）:
  `iverilog -o <out>.vvp ip/ccd_controller/ccd_controller.srcs/src/*.v`
- iverilog 跑通即可,**不需要**保存波形、不需要 `vvp` 跑波形
- 实际波形验证交给用户在 Vivado Simulation 中查看
- 注释只解释大致逻辑，但不要写死计数器计到哪个值，方便”仿真-微调“
- 声明放在使用之前

---

## 3. Verilog 编码风格

### 3.1 文件头

```verilog
`timescale 1ns / 1ps
//==============================================================================
// Module : <module_name>
// Desc   : <一句话描述,后跟可选多行说明>
//==============================================================================
```

旧的 Vivado ISE 风格头(`Company / Engineer / Create Date / Revision`) **删除**。

### 3.2 端口命名

| 类别 | 规则 | 示例 |
|---|---|---|
| 输入 | 小写,`i_` 前缀 | `i_clk`, `i_rst_n`, `i_freq_sel` |
| 输出 | 小写,`o_` 前缀 | `o_sclk_p0`, `o_rg_p90` |
| 双向 | 小写,`io_` 前缀 | `io_data` |

无论该信号是 `wire` 还是 `reg`,端口列表统一写 `i_*` / `o_*`,**不省略**。

### 3.3 内部信号

- `reg` 与组合 / 中间 `wire`:小写 + 下划线,按用途命名(`cnt`, `vstate`, `h_count`)
- 实例化名:`u_<instance_role>`(`u_ccd_phase_gen`, `u_dut`)
- 不允许 `parameter` 与 `reg` 同名混用,内部 `reg` 必须另取名(`period_reg`, `cnt_reg`)
- **同一模块内只使用上升沿触发**。如果需要下降沿同步的信号，则输入一对相位反相的时钟。

### 3.4 参数与常量

- `parameter` / `localparam`:全大写 + 下划线
- 频率 / 时间单位**显式后缀**:`_HZ` / `_KHZ` / `_MHZ` / `_NS` / `_US` / `_MS`
  - 例:`SYS_CLK_FREQ_HZ = 100_000_000`,`SYS_CLK_PERIOD_NS = 10.0`
- 状态编码:`S_IDLE`, `S_VSHIFT`, `S_HSHIFT`(`S_` 前缀或 `_e` 后缀)

---

## 4. IP 核例化

嵌套 IP 核位于 `ip/ccd_controller/ccd_controller.srcs/sources_1/ip/<ip_name>/`,由 Vivado 在 IP 工程中生成,工程重建时随之重建。

每个 IP 核目录下均有 `.veo`（Verilog Instantiation Example）文件，**这就是该 IP 核的 Verilog 例化模板**。

### 4.1 现有 IP 核列表

| IP 核名 | `.veo` 路径 | 用途 |
|---|---|---|
| `mig_7series_0` | `ip/ccd_controller/ccd_controller.srcs/sources_1/ip/mig_7series_0/mig_7series_0.veo` | DDR3 内存控制器（MIG） |
| `wr_ddr3_fifo` | `ip/ccd_controller/ccd_controller.srcs/sources_1/ip/wr_ddr3_fifo/wr_ddr3_fifo.veo` | 写方向异步 FIFO（16→128bit） |
| `rd_ddr3_fifo` | `ip/ccd_controller/ccd_controller.srcs/sources_1/ip/rd_ddr3_fifo/rd_ddr3_fifo.veo` | 读方向异步 FIFO（128→16bit） |

### 4.2 例化步骤

1. **打开对应 IP 核的 `.veo` 文件**，定位到 `//----------- Begin Cut here for INSTANTIATION Template ---// INST_TAG` 与 `// INST_TAG_END ------ End INSTANTIATION Template ---------` 之间的代码块。

2. **将模板复制到 RTL 代码中**，将模板内的 `your_instance_name` 替换为有意义的实例名（遵循 `u_<role>` 命名风格），并将各端口信号连接到实际信号。

3. **例化示例**（已有代码参考，见 4.4）：`src/ccd_ddr.v` 例化 `mig_7series_0`、`src/ccd_frame_buf_ddr_axi_adapter.v` 例化 `wr_ddr3_fifo` / `rd_ddr3_fifo`。

### 4.3 注意事项

- **不要手动修改 `.veo` 文件**——它们是 Vivado 自动生成的，修改会被覆盖。
- **不要复制 `.veo` 中开头的版权声明**，只复制 `INST_TAG` 之间的模板代码。
- **仿真时需要编译 IP 核的 wrapper 文件**（详见 `.veo` 末尾说明），在 Vivado 中 IP 核会自动加入仿真文件列表。
- 如果需要新建 IP 核，请在 Vivado 中通过 IP Catalog 生成，不要在 `.veo` 中手写。
- 当 IP 核参数需要调整时，在 Vivado 中重新配置（Re-Customize IP），重新生成后 `.veo` 会自动更新。

### 4.4 例化示例参考

- `src/ccd_ddr.v` 中例化 `mig_7series_0`（DDR3 控制器）
- `src/ccd_frame_buf_ddr_axi_adapter.v` 中例化 `wr_ddr3_fifo` / `rd_ddr3_fifo`（异步 FIFO）

### 3.5 复位与有效电平

- 低有效信号:**`_n` 后缀**(`rst_n`, `cs_n`)
- 异步复位:注释里显式写"异步复位,低有效"

### 3.6 一位信号类型

所有 1 bit 端口或信号**显式**标注 `wire` 或 `reg`,不省略:

```verilog
input  wire        i_clk;
output reg  [15:0] o_pixel;
reg                state;
wire               state_done;
```

### 3.7 代码布局

- 端口列表:输入在一组,输出一组,每行一个端口 + 行内注释
- `endmodule` 上一行留空行
- 每个 `always` / `assign` 块前用 `// -----` 或单行注释说明功能
- 4 空格缩进,不用 tab
- 行宽建议 ≤ 100 列
- 一个文件只放一个模块，文件名和模块名保持一致

---

## 4. Testbench 约定

- **保持简单**:TB 只产生激励,不要写复杂功能 / 参考模型 / 评分逻辑
- 顶层模块名:`test_<dut_name>`,**不带** `tb_` 前缀
- DUT 例化名:`u_dut`
- 时钟 / 复位 / 控制信号按本规范的 `i_*` 命名
- TB 内 wire 可不加 `o_` 前缀(`wire sclk_p0;` OK),保持视觉简洁
- 波形验证交给用户在 Vivado Simulation 中查看
- 需要明确的 `$finish` 结束仿真

---

## 5. 工作流(本子项目)

### 5.1 工程重建（Vivado，Linux/Windows 通用）

1. Vivado GUI → 新建工程（part=`xc7a100tfgg484-2`），如 `vivado_proj/ccd_controller_hardware`
2. `Settings → IP → Repository` 添加 IP 仓库：`ip/ccd_controller/ccd_controller.srcs`
3. Tcl 控制台: `source scripts/bd.tcl` → 完整重建 `mb_subsystem` 块设计（MIG 配置在脚本内自动生成）
4. 添加约束：`constraint/` 下 `port.xdc`、`clock.xdc`、`debug.xdc`（如新建工程需手动 Add Sources）
5. 生成 IP 输出产物、Create HDL Wrapper、综合/实现/生成 bitstream
6. `Export Hardware`（含 bitstream）→ 得到 `.xsa`，供 Vitis 使用

> `clock.xdc` 引用 BD wrapper 的层次路径（`mb_subsystem_i/mig_7series_0/...`），须在 Create HDL Wrapper **之后**才生效，属正常顺序。

### 5.2 RTL / TB 迭代

1. 修改 `ip/ccd_controller/ccd_controller.srcs/src/` 下的 `.v` 文件
2. `iverilog -o <out>.vvp ip/ccd_controller/ccd_controller.srcs/src/*.v` 验证语法
3. `vvp <out>.vvp` 跑一下确认不崩溃(可选)
4. 用户在 Vivado 中打开工程,跑 Simulation 自行检查波形
5. 完成后按根 AGENTS.md 约定提交 git(中文 commit message)

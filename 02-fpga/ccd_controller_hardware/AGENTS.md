本目录是 FPGA 子项目的 Vivado 工程根。本 AGENTS.md 约定**子项目结构**、**Verilog 编码风格**和 **testbench 写法**,所有在该目录下生成的 `.v` / `.xdc` / TB 文件必须遵守。

---

## 1. 目录结构

```
02-fpga/ccd_controller_hardware/
├── AGENTS.md                     # 本文件 (本子项目约定)
├── ccd_controller_hardware.xpr   # Vivado 工程入口
├── constraints/                  # .xdc 管脚 / 时序约束
├── rtl/                          # 可综合 RTL 源码 (.v)
│   ├── ccd_phase_gen.v
│   └── ccd_driver.v
└── testbench/                    # Vivado Simulation 用 testbench
    └── test_<dut_name>.v
```

> 不要在本目录新建 `sim_*/`,由 Vivado 自动生成。
> 顶层设计模块放在 `rtl/`,TB 放在 `testbench/`,两边名字成对:`ccd_xxx.v` ↔ `test_ccd_xxx.v`。

---

## 2. 语言与工具链

- **使用 Verilog**,不使用 SystemVerilog
- 用 **iverilog** 验证语法:
  `iverilog -o <out>.vvp rtl/*.v testbench/*.v`
- iverilog 跑通即可,**不需要**保存波形、不需要 `vvp` 跑波形
- 实际波形验证交给用户在 Vivado Simulation 中查看

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

### 3.4 参数与常量

- `parameter` / `localparam`:全大写 + 下划线
- 频率 / 时间单位**显式后缀**:`_HZ` / `_KHZ` / `_MHZ` / `_NS` / `_US` / `_MS`
  - 例:`SYS_CLK_FREQ_HZ = 100_000_000`,`SYS_CLK_PERIOD_NS = 10.0`
- 状态编码:`S_IDLE`, `S_VSHIFT`, `S_HSHIFT`(`S_` 前缀或 `_e` 后缀)

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

---

## 4. Testbench 约定

(从根 AGENTS.md "### FPGA > testbench requirements" 迁入并细化)

- **保持简单**:TB 只产生激励,不要写复杂功能 / 参考模型 / 评分逻辑
- 顶层模块名:`test_<dut_name>`,**不带** `tb_` 前缀
- DUT 例化名:`u_dut`
- 时钟 / 复位 / 控制信号按本规范的 `i_*` 命名
- TB 内 wire 可不加 `o_` 前缀(`wire sclk_p0;` OK),保持视觉简洁
- **禁止** `$dumpfile` / `$dumpvars` / `$monitor` / `$display`
- 波形验证交给用户在 Vivado Simulation 中查看

---

## 5. 工作流(本子项目)

1. 改 `rtl/` 或 `testbench/` 下的 `.v` 文件
2. `iverilog -o <out>.vvp rtl/*.v testbench/*.v` 验证语法
3. `vvp <out>.vvp` 跑一下确认不崩溃(可选)
4. 用户在 Vivado 中打开 `.xpr`,跑 Simulation 自行检查波形
5. 完成后按根 AGENTS.md 约定提交 git(中文 commit message)

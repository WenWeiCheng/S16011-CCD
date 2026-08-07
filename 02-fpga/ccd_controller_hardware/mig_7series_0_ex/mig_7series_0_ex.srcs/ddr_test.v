module ddr_test(
  // Inouts
  inout  [31:0]   ddr3_dq,
  inout  [3:0]    ddr3_dqs_n,
  inout  [3:0]    ddr3_dqs_p,
  // Outputs
  output [14:0]   ddr3_addr,
  output [2:0]    ddr3_ba,
  output          ddr3_ras_n,
  output          ddr3_cas_n,
  output          ddr3_we_n,
  output          ddr3_reset_n,
  output [0:0]    ddr3_ck_p,
  output [0:0]    ddr3_ck_n,
  output [0:0]    ddr3_cke,
  output [0:0]    ddr3_cs_n,
  output [3:0]    ddr3_dm,
  output [0:0]    ddr3_odt,
  // Inputs
  input           clk50m,
  input           reset_n,
  // Outputs
  output [1:0]    led
);

  wire pll_locked;
  wire sys_clk_i;
  wire sys_rst;
  wire tg_compare_error;
  wire init_calib_complete;

  assign sys_rst = pll_locked;
  assign led = {tg_compare_error,init_calib_complete};

  clk_wiz_0 clk_wiz_0
  (
    // Clock out ports
    .clk_out1 (sys_clk_i  ), // output clk_out1
    // Status and control signals
    .resetn   (reset_n    ), // input reset
    .locked   (pll_locked ), // output locked
    // Clock in ports
    .clk_in1  (clk50m     )  // input clk_in1
  );

  example_top u_ip_top
  (
    .ddr3_dq              (ddr3_dq            ),
    .ddr3_dqs_n           (ddr3_dqs_n         ),
    .ddr3_dqs_p           (ddr3_dqs_p         ),
    .ddr3_addr            (ddr3_addr          ),
    .ddr3_ba              (ddr3_ba            ),
    .ddr3_ras_n           (ddr3_ras_n         ),
    .ddr3_cas_n           (ddr3_cas_n         ),
    .ddr3_we_n            (ddr3_we_n          ),
    .ddr3_reset_n         (ddr3_reset_n       ),
    .ddr3_ck_p            (ddr3_ck_p          ),
    .ddr3_ck_n            (ddr3_ck_n          ),
    .ddr3_cke             (ddr3_cke           ),
    .ddr3_cs_n            (ddr3_cs_n          ),
    .ddr3_dm              (ddr3_dm            ),
    .ddr3_odt             (ddr3_odt           ),
    .sys_clk_i            (sys_clk_i          ),
    .init_calib_complete  (init_calib_complete),
    .tg_compare_error     (tg_compare_error   ),
    .sys_rst              (sys_rst            )
  );

endmodule


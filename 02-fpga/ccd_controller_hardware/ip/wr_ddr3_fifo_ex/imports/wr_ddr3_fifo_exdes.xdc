################################################################################
# (c) Copyright 2009 - 2013 Xilinx, Inc. All rights reserved.
# 
# This file contains confidential and proprietary information
# of Xilinx, Inc. and is protected under U.S. and
# international copyright and other intellectual property
# laws.
# 
# DISCLAIMER
# This disclaimer is not a license and does not grant any
# rights to the materials distributed herewith. Except as
# otherwise provided in a valid license issued to you by
# Xilinx, and to the maximum extent permitted by applicable
# law: (1) THESE MATERIALS ARE MADE AVAILABLE "AS IS" AND
# WITH ALL FAULTS, AND XILINX HEREBY DISCLAIMS ALL WARRANTIES
# AND CONDITIONS, EXPRESS, IMPLIED, OR STATUTORY, INCLUDING
# BUT NOT LIMITED TO WARRANTIES OF MERCHANTABILITY, NON-
# INFRINGEMENT, OR FITNESS FOR ANY PARTICULAR PURPOSE; and
# (2) Xilinx shall not be liable (whether in contract or tort,
# including negligence, or under any other theory of
# liability) for any loss or damage of any kind or nature
# related to, arising under or in connection with these
# materials, including for any direct, or any indirect,
# special, incidental, or consequential loss or damage
# (including loss of data, profits, goodwill, or any type of
# loss or damage suffered as a result of any action brought
# by a third party) even if such damage or loss was
# reasonably foreseeable or Xilinx had been advised of the
# possibility of the same.
# 
# CRITICAL APPLICATIONS
# Xilinx products are not designed or intended to be fail-
# safe, or for use in any application requiring fail-safe
# performance, such as life-support or safety devices or
# systems, Class III medical devices, nuclear facilities,
# applications related to the deployment of airbags, or any
# other applications that could lead to death, personal
# injury, or severe property or environmental damage
# (individually and collectively, "Critical
# Applications"). Customer assumes the sole risk and
# liability of any use of Xilinx products in Critical
# Applications, subject only to applicable laws and
# regulations governing limitations on product liability.
# 
# THIS COPYRIGHT NOTICE AND DISCLAIMER MUST BE RETAINED AS
# PART OF THIS FILE AT ALL TIMES.
#
################################################################################

# Core Period Constraint. This constraint can be modified, and is
# valid as long as it is met after place and route.
set_false_path -from [get_ports RESET]
set_false_path -from [get_cells fg_pc_*/*_d1_reg]
create_clock -name "TS_RD_CLK" -period 26.060 [ get_ports RD_CLK ]
create_clock -name "TS_WR_CLK" -period 37.744 [ get_ports WR_CLK ]

################################################################################
### CDC Waivers ###
create_waiver -internal -scope -type CDC -id CDC-10 -user fifo_generator  -tags "10966" -from [get_pins -quiet fg_pc_*/sim_done_wr_dom2_reg/C] -to [get_pins -quiet empty_*_wr_reg/D] -description {Waiving CDC-10 as it is coming from example design in case of pass through wire configuration in AXI_Memeory_Mapped}
create_waiver  -type CDC -id CDC-1 -user fifo_generator   -from [get_pins -quiet my_ip_inst/top_inst/U0/inst_fifo_gen/gconvfifo.rf/grf.rf/gntv_or_sync_fifo.mem/gdm.dm_gen.dm/RAM_reg_0_255_0_0/DP.D/CLK] -to [get_pins -quiet my_ip_inst/top_inst/U0/inst_fifo_gen/gconvfifo.rf/grf.rf/gntv_or_sync_fifo.mem/gdm.dm_gen.dm/gpr1.dout_i_reg[0]/D] -description {Waiving CDC-1 warning because it is treating the asynchronous LUTRAM read to the read register path as CDC path which is not a real CDC}
create_waiver  -type CDC -id CDC-1 -user fifo_generator   -from [get_pins -quiet my_ip_inst/top_inst/U0/inst_fifo_gen/gaxis_fifo.gaxisf.axisf/grf.rf/gntv_or_sync_fifo.mem/gdm.dm_gen.dm/RAM_reg_0_31_0_0/DP/CLK] -to [get_pins -quiet my_ip_inst/top_inst/U0/inst_fifo_gen/gaxis_fifo.gaxisf.axisf/grf.rf/gntv_or_sync_fifo.mem/gdm.dm_gen.dm/gpr1.dout_i_reg[0]/D] -description {Waiving CDC-1 warning because it is treating the asynchronous LUTRAM read to the read register path as CDC path which is not a real CDC}
create_waiver  -type CDC -id CDC-1 -user fifo_generator   -from [get_pins -quiet my_ip_inst/top_inst/U0/inst_fifo_gen/gaxis_fifo.gaxisf.axisf/grf.rf/gntv_or_sync_fifo.mem/gdm.dm_gen.dm/RAM_reg_0_31_1_1/DP/CLK] -to [get_pins -quiet my_ip_inst/top_inst/U0/inst_fifo_gen/gaxis_fifo.gaxisf.axisf/grf.rf/gntv_or_sync_fifo.mem/gdm.dm_gen.dm/gpr1.dout_i_reg[1]/D] -description {Waiving CDC-1 warning because it is treating the asynchronous LUTRAM read to the read register path as CDC path which is not a real CDC}



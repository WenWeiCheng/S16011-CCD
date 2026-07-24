-- Copyright 1986-2020 Xilinx, Inc. All Rights Reserved.
-- --------------------------------------------------------------------------------
-- Tool Version: Vivado v.2020.1 (win64) Build 2902540 Wed May 27 19:54:49 MDT 2020
-- Date        : Wed Jul 22 21:17:05 2026
-- Host        : DESKTOP-KD2H86C running 64-bit major release  (build 9200)
-- Command     : write_vhdl -force -mode synth_stub
--               d:/2607-Pro-S16011-CCD/02-fpga/ccd_controller_hardware/ccd_controller_hardware.srcs/sources_1/bd/mb_subsystem/ip/mb_subsystem_clk_wiz_0_1/mb_subsystem_clk_wiz_0_1_stub.vhdl
-- Design      : mb_subsystem_clk_wiz_0_1
-- Purpose     : Stub declaration of top-level module interface
-- Device      : xc7a100tfgg484-2
-- --------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity mb_subsystem_clk_wiz_0_1 is
  Port ( 
    clk_out1 : out STD_LOGIC;
    reset : in STD_LOGIC;
    locked : out STD_LOGIC;
    clk_in1 : in STD_LOGIC
  );

end mb_subsystem_clk_wiz_0_1;

architecture stub of mb_subsystem_clk_wiz_0_1 is
attribute syn_black_box : boolean;
attribute black_box_pad_pin : string;
attribute syn_black_box of stub : architecture is true;
attribute black_box_pad_pin of stub : architecture is "clk_out1,reset,locked,clk_in1";
begin
end;

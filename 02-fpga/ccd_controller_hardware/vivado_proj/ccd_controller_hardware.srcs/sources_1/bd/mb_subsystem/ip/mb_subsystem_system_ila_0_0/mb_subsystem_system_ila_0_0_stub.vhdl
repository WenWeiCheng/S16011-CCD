-- Copyright 1986-2020 Xilinx, Inc. All Rights Reserved.
-- --------------------------------------------------------------------------------
-- Tool Version: Vivado v.2020.1 (win64) Build 2902540 Wed May 27 19:54:49 MDT 2020
-- Date        : Thu Aug  6 19:15:38 2026
-- Host        : DESKTOP-KD2H86C running 64-bit major release  (build 9200)
-- Command     : write_vhdl -force -mode synth_stub -rename_top mb_subsystem_system_ila_0_0 -prefix
--               mb_subsystem_system_ila_0_0_ mb_subsystem_system_ila_0_0_stub.vhdl
-- Design      : mb_subsystem_system_ila_0_0
-- Purpose     : Stub declaration of top-level module interface
-- Device      : xc7a100tfgg484-2
-- --------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity mb_subsystem_system_ila_0_0 is
  Port ( 
    clk : in STD_LOGIC;
    probe0 : in STD_LOGIC_VECTOR ( 0 to 0 )
  );

end mb_subsystem_system_ila_0_0;

architecture stub of mb_subsystem_system_ila_0_0 is
attribute syn_black_box : boolean;
attribute black_box_pad_pin : string;
attribute syn_black_box of stub : architecture is true;
attribute black_box_pad_pin of stub : architecture is "clk,probe0[0:0]";
attribute X_CORE_INFO : string;
attribute X_CORE_INFO of stub : architecture is "bd_9912,Vivado 2020.1";
begin
end;

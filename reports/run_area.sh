#!/bin/bash
LIB=~/pdk/sky130_fd_sc_hd__tt_025C_1v80.lib

yosys -q -p "
read_verilog -sv src/tpu_pkg.sv src/os_pe.sv src/os_array.sv src/host_if.sv src/tt_um_nubavocadofarmer_systolic_tpu.sv
synth -top tt_um_nubavocadofarmer_systolic_tpu
dfflibmap -liberty $LIB
abc -liberty $LIB
opt_clean
tee -o reports/area_sky130_yosys.txt stat -liberty $LIB
"
grep -E "^=== |Chip area" reports/area_sky130_yosys.txt

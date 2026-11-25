# =============================================================================
# create_project.tcl — regenerate the Vivado project from source.
#
# Usage (from repo root):
#   vivado -mode batch -source hw/scripts/create_project.tcl
#
# Why TCL instead of committing the .xpr: Vivado project directories are huge,
# full of generated files, and merge terribly. A script that rebuilds the
# project from RTL + constraints is the real source of truth, and it's diffable.
# =============================================================================

set script_dir  [file dirname [file normalize [info script]]]
set hw_dir      [file normalize "$script_dir/.."]
set proj_name   "kv260_llm"
set proj_dir    "$hw_dir/build/$proj_name"

# K26 SOM on the KV260 carrier. Using the board part pulls in the right DDR,
# clocks, and MIO setup for the Zynq PS automatically.
# TODO (Phase 0): confirm the exact board_part string installed with your Vivado
# version:  get_board_parts *kv260*
set board_part  "xilinx.com:kv260_som:part0:1.4"
set fpga_part   "xck26-sfvc784-2LV-c"

create_project $proj_name $proj_dir -part $fpga_part -force
catch { set_property board_part $board_part [current_project] }

# RTL sources
add_files -fileset sources_1 [glob -nocomplain $hw_dir/rtl/*.sv]

# Constraints
add_files -fileset constrs_1 [glob -nocomplain $hw_dir/constraints/*.xdc]

# TODO (Phase 0):
#   - create the block design: Zynq UltraScale+ PS + AXI DMA + AXI interconnect
#   - make_wrapper, set top, launch synth/impl, write_bitstream

puts "Project created at $proj_dir"

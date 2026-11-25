# Verilator simulation for the RTL testbenches.
#   make            build + run tb_matvec_int8
#   make trace      same, but dump a VCD waveform (open with GTKWave / Surfer)
#   make clean
#
# Requires Verilator >= 5.0 (for --timing, which lets a plain SystemVerilog
# testbench use delays like `#5` and `@(posedge clk)`).

TOP      ?= tb_matvec_int8
RTL_DIR  := ../rtl
SOURCES  := $(RTL_DIR)/matvec_int8.sv $(TOP).sv

VERILATOR_FLAGS := --binary --timing -Wall -Wno-fatal --top-module $(TOP) -j 0

.PHONY: all run trace clean

all: run

obj_dir/V$(TOP): $(SOURCES)
	verilator $(VERILATOR_FLAGS) --trace $(SOURCES)

run: obj_dir/V$(TOP)
	./obj_dir/V$(TOP)

trace: obj_dir/V$(TOP)
	./obj_dir/V$(TOP) +trace

clean:
	rm -rf obj_dir *.vcd

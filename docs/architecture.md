# Architecture

> Living document. Describes what exists today and, clearly marked, what's planned.

## What exists today

- **`hw/rtl/matvec_int8.sv`**: a starter int8 matvec engine, simulation only. Activations live in an on-chip RAM, int8 weights stream in over valid/ready, and LANES MACs per cycle feed an int32 accumulator, giving one result per row. It hasn't been synthesized yet, and there's no AXI or DMA.
- **`hw/tb/tb_matvec_int8.sv`**: a self-checking Verilator testbench with random backpressure.
- **`runtime/src/matvec.c`**: CPU fp32 matvec plus an int8 reference matvec that matches the RTL's arithmetic.
- **`runtime/net/`**: TCP helpers (send_all/recv_all, TCP_NODELAY), not used yet.

## Planned

### Matvec engine (PL)

```
 DDR ──AXI DMA──► weight stream ──► dequant ──► LANES × DSP MAC ──► adder tree ──► accumulator ──► y
                                                     ▲
                                  activation BRAM/URAM (loaded once per matvec)
```

- AXI4-Stream weight input fed by AXI DMA, plus AXI-Lite control registers
- Per-group scale dequantization on the fly
- Weights pre-tiled in DDR so DMA reads are long contiguous bursts

### Runtime (PS)

- Starts from llama2.c: model loading, tokenizer, attention, softmax, sampling on the A53 cores
- `matmul()` dispatches to the CPU or FPGA backend

### Multi-board

- Pipeline parallelism (split by layers), then tensor parallelism (split every matrix)
- Plain TCP sockets on the ARM side

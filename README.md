# kv260-llm-cluster

Distributed LLM inference on a cluster of AMD Kria KV260 FPGA boards, built from scratch: my own matrix-multiply engine in SystemVerilog, a C runtime on the ARM cores, and Ethernet between the boards.

> **Status:** Early. Nothing runs yet. Phase 0 (board bring-up) is in progress. Everything below is a plan unless it says otherwise.

---

## Why

I've wanted to do a Verilog/FPGA project for a while and never had a good enough excuse. I finally picked up a KV260, and I'm using it to learn hardware design by building something I care about instead of doing tutorials in a vacuum.

I'm a CS student heading toward AI and infrastructure product work. I'd like to understand how inference actually works, from the DSP slices up, and not just from the blog-post level.

## The point (it's not speed)

A laptop CPU will beat this cluster. I know that going in.

What I actually want to understand is why LLM inference looks the way it does. At batch size 1, generating each token means streaming every weight in the model through the compute units once. That makes decode **memory-bandwidth bound**, not compute bound:

```
tokens/sec  ≲  memory bandwidth  ÷  bytes of weights read per token
```

So the questions I'm building toward are:

- **How close can a custom datapath get to that ceiling?** And what eats the gap: DMA overhead, AXI inefficiency, CPU-side work, my own bad RTL?
- **Hardware/software co-design.** What belongs in the fabric vs. on the CPU, and why?
- **Quantization.** fp32 → int8 → int4: what do you gain in speed and memory, and what do you lose in quality?
- **Distributed inference.** What do pipeline and tensor parallelism actually cost over cheap gigabit Ethernet? Part of the goal is to feel firsthand why NVLink, HBM, and purpose-built chips (Groq, Cerebras, Etched) exist.
- **FPGA design itself.** RTL, testbenches, AXI, DMA, timing closure, and the Vivado/Vitis toolchain. I'm a beginner here, and that's the honest starting point.

## Hardware

| | Single KV260 | 4-board cluster |
|---|---|---|
| SoC | Zynq UltraScale+ MPSoC (K26 SOM) | 4× |
| CPU | Quad-core Arm Cortex-A53, Ubuntu 24.04 LTS | 16 cores |
| Logic cells | ~256K | ~1M |
| DSP slices | 1,248 | 4,992 |
| Block RAM | 144 × 36 Kb ≈ 5.1 Mb | ≈ 20.4 Mb |
| UltraRAM | 64 × 288 Kb ≈ 18 Mb | ≈ 72 Mb |
| Distributed (LUT) RAM | ≈ 3.5 Mb | ≈ 14 Mb |
| DRAM | 4 GB DDR4, 64-bit, 2400 MT/s | 16 GB |
| DRAM bandwidth (theoretical peak) | ~19.2 GB/s | ~76.8 GB/s aggregate |
| Network | Gigabit Ethernet | Unmanaged gigabit switch |

The three on-chip memories add up to AMD's quoted ~26.6 Mb. UltraRAM matters most for this design: it's where the large activation buffers will go.

19.2 GB/s is a theoretical peak (2400 MT/s × 8 bytes). The CPU and the fabric share it, so the fabric will see noticeably less. Measuring the real DMA throughput is part of Phase 0, and that measured number becomes the practical ceiling for the results table.

## Architecture (planned)

### Single node

The ARM cores (the "PS," or processing system) run the inference runtime in C. The FPGA fabric (the "PL," or programmable logic) runs a matrix-vector engine. Matvec is the dominant op at batch size 1. The engine streams weights straight from DDR, dequantizes them on the fly, and multiplies them against activations held in on-chip BRAM/URAM.

```
┌───────────────────────────── KV260 ─────────────────────────────┐
│                                                                 │
│  PS: 4× Cortex-A53 (Ubuntu)            PL: FPGA fabric          │
│  ┌──────────────────────────┐          ┌──────────────────────┐ │
│  │ C runtime (from llama2.c)│  AXI-Lite│  Matvec engine       │ │
│  │  - tokenizer             │ ───────► │   control regs       │ │
│  │  - attention, softmax    │  (ctrl)  │                      │ │
│  │  - sampling              │          │  ┌────────────────┐  │ │
│  │  - networking (sockets)  │          │  │ activations    │  │ │
│  └────────────┬─────────────┘          │  │ BRAM / URAM    │  │ │
│               │                        │  └───────┬────────┘  │ │
│               │                        │          ▼           │ │
│               │                        │  dequant → DSP MAC   │ │
│               │                        │          array       │ │
│               │                        └──────────▲───────────┘ │
│               │                                   │ AXI (DMA)   │
│               ▼                                   │ weight      │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │ DDR4 4 GB: weights (pre-tiled for the engine), KV cache  │   │
│  └──────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

### Multi-node: pipeline vs. tensor parallelism

**Pipeline parallelism:** split the model by layers. Each board owns a contiguous chunk and passes the activation vector to the next board. Traffic is small (one hidden-state vector per hop), but at batch 1 only one board is working at any moment.

```
token ─► [Board 0: layers  0–5 ] ─► [Board 1: layers  6–11] ─►
         [Board 2: layers 12–17] ─► [Board 3: layers 18–21] ─► logits
                    (one board active at a time)
```

The uneven split is deliberate. The last board also holds the output layer, which turns the final hidden state into word probabilities. For TinyLlama that's 32,000 × 2048 ≈ 65M parameters, all read on every token. That's about 1.5 transformer layers' worth (≈44M parameters each), so 4 layers plus the output layer comes to roughly 5.5 layer-equivalents of memory reads, close to the 6 on every other board. The first board's embedding table is nearly free, because each token reads only one row of it.

**Tensor parallelism:** split every layer's weight matrices across all four boards. Every board works on every layer at once, so aggregate bandwidth is used in parallel. The catch is that the boards have to sync (all-reduce / all-gather) several times per layer.

```
            ┌─► [Board 0: ¼ of W] ─┐
x (layer) ──┼─► [Board 1: ¼ of W] ─┼─► all-reduce over Ethernet ─► next layer
            ├─► [Board 2: ¼ of W] ─┤
            └─► [Board 3: ¼ of W] ─┘
            (all boards active, sync every layer)
```

At batch 1 those syncs move tiny amounts of data, so I expect **network latency, not bandwidth,** to be what matters. Measuring that is one of the core goals.

## Roadmap

| Status | Phase | Goal | Model | Boards |
|---|---|---|---|---|
| ⬜ | 0 | Board bring-up: Ubuntu on Kria, Vivado/Vitis, blinky, AXI DMA loopback, measure real DMA throughput | — | 1 |
| ⬜ | 1 | Pure-C inference on the A53s (CPU baseline) | stories15M → 110M | 1 |
| ⬜ | 2 | Matvec engine in the PL, offload matmuls, int8 weights | stories110M | 1 |
| ⬜ | 3 | Pipeline parallelism over Ethernet | stories110M → TinyLlama | 2 → 4 |
| ⬜ | 4 | Tensor parallelism, latency-optimized collectives | TinyLlama 1.1B | 4 |
| ⬜ | 5 | Stretch: int4, speculative decoding, FPGA-side networking | TinyLlama 1.1B | 4 |

Phase 0 is next. Each phase ends with a git tag (`v0.1-phase1`, …), an entry in [`bench/results.md`](bench/results.md), and a devlog post in [`docs/devlog/`](docs/devlog/).

## Models

| Model | Params | Source | License |
|---|---|---|---|
| stories15M | 15M | [karpathy/llama2.c](https://github.com/karpathy/llama2.c) | Weights MIT ([karpathy/tinyllamas](https://huggingface.co/karpathy/tinyllamas)); trained on [TinyStories](https://huggingface.co/datasets/roneneldan/TinyStories) (CDLA-Sharing-1.0) |
| stories110M | 110M | [karpathy/llama2.c](https://github.com/karpathy/llama2.c) | Weights MIT ([karpathy/tinyllamas](https://huggingface.co/karpathy/tinyllamas)); trained on [TinyStories](https://huggingface.co/datasets/roneneldan/TinyStories) (CDLA-Sharing-1.0) |
| TinyLlama-1.1B | 1.1B | [TinyLlama](https://github.com/jzhang38/TinyLlama) | Apache-2.0 |

The runtime starts from llama2.c. **Model weights are not committed to this repo.** A download script will fetch them (planned: `scripts/download_models.sh`).

## Back-of-envelope ceilings

> ⚠️ **These are theoretical upper bounds, not results.** They take bandwidth only: theoretical DDR bandwidth ÷ weight size. Real numbers will be lower, maybe a lot lower. Finding out how much lower, and why, is the point.

| Setup | Weights | Theoretical ceiling |
|---|---|---|
| 1 board, stories110M fp32 | ~440 MB | ~44 tok/s |
| 1 board, stories110M int8 | ~110 MB | ~175 tok/s |
| 4 boards pipeline, TinyLlama int8 | ~1.1 GB | ~17 tok/s (one board active at a time at batch 1) |
| 4 boards tensor-parallel, TinyLlama int8 | ~1.1 GB | ~70 tok/s, *before* network overhead |

## Results

Nothing measured yet.

| Phase | Setup | Model | Precision | Prefill tok/s | Decode tok/s | % of ceiling |
|---|---|---|---|---|---|---|
| 1 | 1 board, CPU only | stories110M | fp32 | TBD | TBD | TBD |
| 2 | 1 board, PL matvec | stories110M | int8 | TBD | TBD | TBD |
| 3 | 4 boards, pipeline | TinyLlama 1.1B | int8 | TBD | TBD | TBD |
| 4 | 4 boards, tensor-parallel | TinyLlama 1.1B | int8 | TBD | TBD | TBD |

"% of ceiling" will be measured against the DMA throughput from Phase 0, not just the theoretical 19.2 GB/s.

**Methodology:** fixed prompt and seed, 256 generated tokens, median of 5 runs, with decode and prefill reported separately. Full details will live in [`bench/README.md`](bench/README.md).

## Repo layout (planned)

None of this exists yet. It'll fill in phase by phase.

```
docs/
  architecture.md       design notes
  setup-kv260.md        board bring-up guide
  devlog/               one post per phase
hw/
  rtl/                  SystemVerilog source
  tb/                   testbenches (Verilator / cocotb)
  constraints/          XDC constraints
  scripts/              Vivado TCL to regenerate the project
runtime/
  src/                  C inference runtime
  net/                  socket-based inter-board comms
  Makefile
scripts/
  download_models.sh
  export_quantized.py
bench/
  README.md             benchmark methodology
  run_bench.sh
  results.md
```

## Getting started

Coming soon. Once Phase 0 is done, [`docs/setup-kv260.md`](docs/setup-kv260.md) will walk through flashing Ubuntu 24.04 LTS, installing the toolchain, and building the first bitstream. Right now it's just a placeholder.

## Design decisions

- **Networking on the ARM side, with plain Linux sockets.** Doing Ethernet in the fabric would cost months before I learned anything about inference. I may revisit this in Phase 5 if collective latency turns out to dominate.
- **The fabric does matvec, and only matvec at first.** It's where almost all the bytes and FLOPs are at batch 1. Attention, softmax, the tokenizer, and sampling stay on the CPU until there's a measured reason to move them.
- **Stream weights, keep activations on chip.** Weights are far too big for on-chip RAM, so they stream from DDR. The activation vector is small, so it lives in BRAM/URAM and gets reused across every row.
- **Dequantize on the fly.** Store int8 (later int4) in DDR to cut the bytes moved, and expand to the MAC's working precision inside the engine.
- **Pre-tile weights in DDR.** Lay weights out offline to match the engine's access pattern, so DMA does long sequential bursts instead of scattered reads.

## Open questions

- Does tensor parallelism over gigabit Ethernet actually beat pipeline parallelism at batch 1? Where's the crossover as model size changes?
- How much latency does a Linux socket round-trip add per sync? TinyLlama needs roughly 44 syncs per token (2 per layer × 22 layers), against a theoretical bandwidth floor of ~14 ms per token on 4 boards. Is per-sync latency small enough next to that floor for tensor parallelism to win?
- Can UDP plus busy-polling get per-sync latency low enough to matter? Does pinning the network thread to its own core help further, or is that where FPGA-side networking becomes worth it?
- What fraction of theoretical DDR bandwidth can the PL realistically pull through the AXI ports while the CPU is also using memory?
- How much quality does int8 lose on these small models, and does int4 break them?
- Once matvec is offloaded, how much does the CPU-side work (attention, softmax) start to matter?

## Acknowledgments

- [karpathy/llama2.c](https://github.com/karpathy/llama2.c): the runtime starting point and the stories models.
- [TinyLlama](https://github.com/jzhang38/TinyLlama): the 1.1B model.
- AMD's Kria KV260 and K26 SOM documentation.

## License

The code in this repo is MIT-licensed. See [LICENSE](LICENSE). Model weights and datasets aren't part of this repo and have their own licenses (see [Models](#models)).

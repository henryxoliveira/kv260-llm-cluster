# Benchmark methodology

Every number in [`results.md`](results.md) and the main README follows these rules. If a run doesn't, it doesn't go in the table.

## Rules

- **Fixed prompt and seed.** Same prompt text and sampler seed for every run, so runs can be compared.
- **256 generated tokens** per run.
- **Median of 5 runs.** Report the median, not the best run.
- **Prefill and decode reported separately.** Prefill (processing the prompt) and decode (generating one token at a time) stress the hardware differently, so mixing them hides what's going on.
- **Compare against the ceiling.** Report each decode number as a % of the bandwidth ceiling: `measured DMA bandwidth ÷ weight bytes`. The Phase 0 measured DMA number is the ceiling, not the theoretical 19.2 GB/s.
- **Never invent numbers.** Anything theoretical gets labeled theoretical.

## Recorded alongside each result

- git commit hash
- Board revision, Ubuntu image, and kernel version
- Model, precision, and number of boards
- Bitstream / engine configuration (e.g. LANES, clock frequency)

## Running

```bash
bench/run_bench.sh <model.bin> [backend]
```

See [`run_bench.sh`](run_bench.sh). It's a starter script; the runtime doesn't generate text yet.

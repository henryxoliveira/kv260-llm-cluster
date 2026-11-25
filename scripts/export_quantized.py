#!/usr/bin/env python3
"""export_quantized.py — quantize llama2.c fp32 weights to int8 (starter).

STATUS: stub. Today it only reads the llama2.c header and reports the model
shape. It does not write a quantized file yet.

Plan:
  1. Read the llama2.c .bin (7-int header, then fp32 tensors).
  2. Quantize each weight matrix to int8 with per-group scales
     (same idea as llama2.c's export.py "version 2").
  3. Re-tile each matrix to match the FPGA engine's access pattern (row-major,
     LANES-wide beats; see hw/rtl/matvec_int8.sv) so DMA can stream it with
     long contiguous bursts.

Usage: scripts/export_quantized.py models/stories15M.bin
"""
import struct
import sys
from pathlib import Path

HEADER_FIELDS = ("dim", "hidden_dim", "n_layers", "n_heads", "n_kv_heads", "vocab_size", "seq_len")


def read_header(path: Path) -> dict:
    with path.open("rb") as f:
        values = struct.unpack("7i", f.read(7 * 4))
    cfg = dict(zip(HEADER_FIELDS, values))
    # llama2.c convention: a negative vocab_size means the classifier weights
    # are NOT shared with the token embedding table.
    cfg["shared_classifier"] = cfg["vocab_size"] > 0
    cfg["vocab_size"] = abs(cfg["vocab_size"])
    return cfg


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__)
        return 1
    path = Path(sys.argv[1])
    cfg = read_header(path)
    for k, v in cfg.items():
        print(f"{k:>18}: {v}")
    print(f"{'file size':>18}: {path.stat().st_size / 1e6:.1f} MB (fp32)")
    print("TODO: int8 quantization + tiling not implemented yet.")
    return 0


if __name__ == "__main__":
    sys.exit(main())

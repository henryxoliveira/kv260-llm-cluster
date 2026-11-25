#!/usr/bin/env bash
# run_bench.sh — run the standard benchmark (see bench/README.md).
#
# STATUS: starter. The runtime can't generate text yet, so this only sets up
# the fixed parameters and the 5-run loop. The parsing of prefill/decode tok/s
# gets filled in once the runtime prints them.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODEL="${1:?usage: $0 <model.bin> [backend]}"
BACKEND="${2:-cpu}"

# Fixed parameters (bench/README.md). Change only with a methodology note.
PROMPT="Once upon a time"
SEED=42
STEPS=256
RUNS=5

echo "commit:  $(git -C "$REPO_ROOT" rev-parse --short HEAD)"
echo "host:    $(uname -srm)"
echo "model:   $MODEL   backend: $BACKEND"
echo "prompt:  \"$PROMPT\"   seed: $SEED   steps: $STEPS   runs: $RUNS"

for run in $(seq 1 "$RUNS"); do
    echo "--- run $run/$RUNS ---"
    # TODO: replace with the real generate command once it exists, e.g.
    # "$REPO_ROOT/runtime/build/kvllm" "$MODEL" -i "$PROMPT" -s "$SEED" -n "$STEPS" -b "$BACKEND"
    echo "TODO: runtime generation not implemented yet"
done

# TODO: collect per-run prefill/decode tok/s and print the median of each.

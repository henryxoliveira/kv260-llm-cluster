#!/usr/bin/env bash
# download_models.sh — fetch model weights into ./models (git-ignored; never commit weights).
#
# Usage: scripts/download_models.sh [stories15M|stories110M|tokenizer|all]
#
# stories15M / stories110M: karpathy/tinyllamas on Hugging Face (weights MIT;
# trained on TinyStories, CDLA-Sharing-1.0). These are llama2.c-format .bin files.
# TinyLlama-1.1B (Apache-2.0) gets added in a later phase, once the export path exists.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODEL_DIR="$REPO_ROOT/models"
HF_BASE="https://huggingface.co/karpathy/tinyllamas/resolve/main"
TOKENIZER_URL="https://raw.githubusercontent.com/karpathy/llama2.c/master/tokenizer.bin"

mkdir -p "$MODEL_DIR"

fetch() {  # fetch <url> <dest>
    local url="$1" dest="$2"
    if [[ -f "$dest" ]]; then
        echo "already have $(basename "$dest")"
        return
    fi
    echo "downloading $(basename "$dest") ..."
    curl -fL --progress-bar -o "$dest.part" "$url"
    mv "$dest.part" "$dest"
}

case "${1:-stories15M}" in
    stories15M)  fetch "$HF_BASE/stories15M.bin"  "$MODEL_DIR/stories15M.bin" ;;
    stories110M) fetch "$HF_BASE/stories110M.bin" "$MODEL_DIR/stories110M.bin" ;;
    tokenizer)   fetch "$TOKENIZER_URL"           "$MODEL_DIR/tokenizer.bin" ;;
    all)
        fetch "$HF_BASE/stories15M.bin"  "$MODEL_DIR/stories15M.bin"
        fetch "$HF_BASE/stories110M.bin" "$MODEL_DIR/stories110M.bin"
        fetch "$TOKENIZER_URL"           "$MODEL_DIR/tokenizer.bin"
        ;;
    *) echo "usage: $0 [stories15M|stories110M|tokenizer|all]" >&2; exit 1 ;;
esac

ls -lh "$MODEL_DIR"

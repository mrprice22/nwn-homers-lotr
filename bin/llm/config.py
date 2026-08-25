"""Harness configuration.

Everything host-specific lives here so the harness can be relocated to another
machine without edits elsewhere. Every value can be overridden by an env var.
"""
from __future__ import annotations

import os
from pathlib import Path

# Repo root: bin/llm/config.py -> bin/llm -> bin -> repo
REPO = Path(os.environ.get("LLM_REPO") or Path(__file__).resolve().parents[2])

# The Ollama box. Plain HTTP on the LAN with no authentication -- never send
# secrets here (server.env, CD keys, bin/seed-admindb.sh, merit aliases).
OLLAMA_URL = os.environ.get("LLM_OLLAMA_URL", "http://192.168.1.103:11434")

# Model registry. Measured on this hardware 2026-08-23:
#   31B  2.2 tok/s  -- never use for bulk, it is 4x slower than 12B for one file
#   12B  ~8 tok/s   -- the default: best quality/speed tradeoff
#   E4B  ~12 tok/s  -- fastest, but noticeably purpler prose; bulk/low-stakes only
MODELS = {
    "default": "hf.co/unsloth/gemma-4-12B-it-GGUF:UD-Q4_K_XL",
    "fast": "hf.co/unsloth/gemma-4-E4B-it-GGUF:Q8_0",
    "best": "hf.co/unsloth/gemma-4-31B-it-GGUF:UD-Q4_K_XL",
}

# Candidate embedding models, in preference order. None may be installed; the
# client probes and callers fall back. NB: `--embeddings` is a llama.cpp flag,
# not an Ollama one -- the fix is `ollama pull embeddinggemma`.
EMBED_MODELS = ("embeddinggemma", "nomic-embed-text", "bge-m3")

# 4 parallel requests measured ~2.5x the aggregate throughput of 1.
CONCURRENCY = int(os.environ.get("LLM_CONCURRENCY", "4"))
TIMEOUT = float(os.environ.get("LLM_TIMEOUT", "300"))
RETRIES = int(os.environ.get("LLM_RETRIES", "3"))

CACHE_DIR = Path(os.environ.get("LLM_CACHE_DIR") or REPO / ".llm-cache")
LEDGER_DIR = Path(os.environ.get("LLM_LEDGER_DIR") or REPO / "llm-changes")
LOCK_PATH = REPO / ".llm-harness.lock"

UNPACKED = REPO / "unpacked"
DOCS = REPO / "docs"
MODULE_INDEX = REPO / "module-index"

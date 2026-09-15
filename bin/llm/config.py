"""Harness configuration.

Everything host-specific lives here so the harness can be relocated to another
machine without edits elsewhere. Every value can be overridden by an env var.
"""
from __future__ import annotations

import os
from pathlib import Path

# Repo root: bin/llm/config.py -> bin/llm -> bin -> repo
REPO = Path(os.environ.get("LLM_REPO") or Path(__file__).resolve().parents[2])

# The LLM box. Plain HTTP on the LAN with no authentication -- never send
# secrets here (server.env, CD keys, bin/seed-admindb.sh, merit aliases).
#
# Since 2026-09-14 this is **llama.cpp's `llama-server`**, not Ollama, on the
# machine wired to this box over ethernet (this host runs the shared connection,
# so it is 10.42.0.1 and the box is a DHCP client of it). The client speaks the
# OpenAI-compatible API (`/v1/...`), which both servers implement, so the switch
# is a URL change rather than a rewrite.
#
# Two things have to be true on that machine or nothing here can connect, and
# both fail as a *hang* rather than a refusal:
#   * llama-server must be started with `--host 0.0.0.0` -- it binds 127.0.0.1
#     by default, which is not reachable from anywhere but itself.
#   * its port must be allowed through that machine's firewall for this subnet.
# Verified 2026-09-14: bound to 0.0.0.0:8080, /health 200 over the LAN IP.
LLM_URL = os.environ.get("LLM_URL") or os.environ.get(
    "LLM_OLLAMA_URL", "http://10.42.0.83:8080")
# Old name, still read by anything that imports it.
OLLAMA_URL = LLM_URL

# Model registry. **llama-server serves exactly one model** -- the one it was
# started with -- and ignores the `model` field of a request, so these aliases
# are labels for the picker rather than a choice the box can honour. Switching
# models means restarting llama-server with a different `-m`. The name still
# matters here: it is part of every cache key and flavor fingerprint, so it must
# change when the loaded model does, or the new model returns the old one's
# cached answers.
# The name is the server's --alias, which is what /v1/models reports and what a
# request must name. Currently: Qwen3.6-35B-A3B Q4_K_M, an MoE with 3B active,
# ~25.8 tok/s generation, ~24s cold start off NVMe, 16384 context as launched.
MODELS = {
    "default": os.environ.get("LLM_MODEL", "qwen36"),
}

# Candidate embedding models, in preference order. None may be served; the
# client probes and callers fall back. A llama-server only has these if it was
# started with `--embeddings` (and one embedding model per server), so on this
# box the answer is usually "none" and callers take their fallback path.
EMBED_MODELS = ("embeddinggemma", "nomic-embed-text", "bge-m3")

# **1, because llama-server serializes.** It processes requests in order, so
# fanning out buys nothing but queueing -- unlike Ollama, where 4 parallel
# requests measured ~2.5x the aggregate throughput of 1. Batch on this side.
CONCURRENCY = int(os.environ.get("LLM_CONCURRENCY", "1"))
TIMEOUT = float(os.environ.get("LLM_TIMEOUT", "300"))
RETRIES = int(os.environ.get("LLM_RETRIES", "3"))

CACHE_DIR = Path(os.environ.get("LLM_CACHE_DIR") or REPO / ".llm-cache")
LEDGER_DIR = Path(os.environ.get("LLM_LEDGER_DIR") or REPO / "llm-changes")
LOCK_PATH = REPO / ".llm-harness.lock"

UNPACKED = REPO / "unpacked"
DOCS = REPO / "docs"
MODULE_INDEX = REPO / "module-index"

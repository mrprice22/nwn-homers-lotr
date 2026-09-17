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
# Since 2026-09-14 this is **llama.cpp**, not Ollama, on the machine wired to
# this box over ethernet (this host runs the shared connection, so it is
# 10.42.0.1 and the box is a DHCP client of it). The client speaks the
# OpenAI-compatible API (`/v1/...`), which every one of these servers
# implements, so a move is a URL change rather than a rewrite.
#
# Since 2026-09-15 it is a **router**, not a single `llama-server`: one endpoint
# serves every model in the box's `LLM CONFIG\models.ini`, the `model` field of
# a request picks one, and the router loads it on demand and unloads it after 15
# idle minutes. `MODELS` below is therefore a real choice again -- see it.
#
# Two things have to be true on that machine or nothing here can connect, and
# both fail as a *hang* rather than a refusal:
#   * the router must be started with its bind host 0.0.0.0 -- llama.cpp binds
#     127.0.0.1 by default, which is not reachable from anywhere but itself.
#   * its port must be allowed through that machine's firewall for this subnet.
# Verified 2026-09-15: bound to 0.0.0.0:8080, three models listed over the LAN.
LLM_URL = os.environ.get("LLM_URL") or os.environ.get(
    "LLM_OLLAMA_URL", "http://10.42.0.83:8080")
# Old name, still read by anything that imports it.
OLLAMA_URL = LLM_URL

# Model registry -- the names the router actually answers to, which is what the
# roadmap editor's release-note picker offers. A name must match a section in
# the box's `models.ini` exactly, and a model added there does not appear until
# the router is restarted; `/v1/models` is the live list.
#
# The name is also part of every cache key and flavor fingerprint, which is what
# makes switching models safe: a new model never returns the previous one's
# cached answers.
#
# **models-max on the box is 1.** Asking for a different model evicts the loaded
# one, so alternating between two per request spends most of its time reloading
# weights. Batch the work for one model, then switch.
MODELS = {
    # Kept because --model defaults to it and old sidecars name it.
    "default": os.environ.get("LLM_MODEL", "qwen36"),
    "qwen36": "qwen36",
    "deepseek9b": "deepseek9b",
    "deepseek": "deepseek",
}

# What the picker shows: alias -> (label, one-line hint). Measured on the box
# 2026-09-15 (Ryzen 7 9700X, 61.7 GB RAM, RTX 3060 8 GB).
MODEL_INFO = {
    "qwen36": (
        "qwen36 — Qwen3.6 35B-A3B Q4_K_M",
        "Default. ~42 tok/s, ~510 tok/s reading, 32K context. Best quality per "
        "second, and the only one here whose thinking can be switched off.",
    ),
    "deepseek9b": (
        "deepseek9b — Qwen3.5 9B distilled from DeepSeek-V4-Flash",
        "~40 tok/s but 3.2x faster at reading (~1630 tok/s), 16K context. Pick "
        "it when the input is the expensive part. Always thinks.",
    ),
    "deepseek": (
        "deepseek — DeepSeek-V4-Flash 0731 UD-IQ1_S",
        "~4 tok/s and minutes to load off NVMe; a 1-bit quant of a model that "
        "wants 8xH100. One hard question you will walk away from — never put it "
        "behind a button someone is waiting on.",
    ),
}

# Only qwen36 honours `chat_template_kwargs.enable_thinking`. Both DeepSeek
# models ignore it silently and always emit a reasoning block, which is why they
# need a generous token budget (see MIN_PREDICT) -- on too small a budget the
# whole budget goes into thinking and `content` comes back empty.
THINKING_OPTIONAL = {"qwen36"}

# Floor on `num_predict` for the models that always reason, measured against
# empty answers: deepseek9b emitted ~500 characters of reasoning on a trivial
# question and answered cleanly at 600; deepseek needed 400 for three words.
MIN_PREDICT = {"deepseek9b": 600, "deepseek": 2000}

# Candidate embedding models, in preference order. None may be served; the
# client probes and callers fall back. The router only serves what models.ini
# lists and none of those is an embedding model, so on this box the answer is
# still "none" and callers take their fallback path.
EMBED_MODELS = ("embeddinggemma", "nomic-embed-text", "bge-m3")

# **1, because the box serializes.** It processes requests in order, so fanning
# out buys nothing but queueing -- unlike Ollama, where 4 parallel requests
# measured ~2.5x the aggregate throughput of 1. Batch on this side.
CONCURRENCY = int(os.environ.get("LLM_CONCURRENCY", "1"))
TIMEOUT = float(os.environ.get("LLM_TIMEOUT", "300"))

# Per-model request timeout. The default 300s is sized for qwen36 warm; it is
# nowhere near enough for a model that generates at 4 tok/s and can spend many
# minutes paging 82.5 GB of weights off NVMe before the first token. An explicit
# LLM_TIMEOUT wins over all of this.
MODEL_TIMEOUT = {"qwen36": 600.0, "deepseek9b": 600.0, "deepseek": 3600.0}


def timeout_for(model: str) -> float:
    """Seconds to wait on `model`, honouring an explicit LLM_TIMEOUT."""
    if os.environ.get("LLM_TIMEOUT"):
        return TIMEOUT
    return MODEL_TIMEOUT.get(model, TIMEOUT)


RETRIES = int(os.environ.get("LLM_RETRIES", "3"))

CACHE_DIR = Path(os.environ.get("LLM_CACHE_DIR") or REPO / ".llm-cache")
LEDGER_DIR = Path(os.environ.get("LLM_LEDGER_DIR") or REPO / "llm-changes")
LOCK_PATH = REPO / ".llm-harness.lock"

UNPACKED = REPO / "unpacked"
DOCS = REPO / "docs"
MODULE_INDEX = REPO / "module-index"

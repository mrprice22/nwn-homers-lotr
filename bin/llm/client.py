"""Ollama client for the local Gemma box.

Deliberately stdlib-only (urllib + threads) to match the rest of bin/, which
depends on nothing but PyYAML.

Three things every call gets, because they were all needed in practice:
  * think=False   -- Gemma 4 otherwise emits a `<|channel>thought` preamble that
                     is not valid output and not separable from the answer.
  * a JSON schema -- structured output is honoured, so responses are parsed,
                     never scraped out of prose.
  * a disk cache  -- keyed on model+prompt+schema+prompt_version, so re-runs and
                     retries after a crash cost nothing, and editing a prompt
                     invalidates exactly the entries it should.
"""
from __future__ import annotations

import hashlib
import json
import re
import threading
import time
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass, field
from typing import Any, Callable, Iterable, Sequence

# Importable both as `python3 -m llm.<mod>` and as `python3 bin/llm/<mod>.py`,
# which is how every other tool in bin/ is invoked.
if __package__ in (None, ""):
    import pathlib as _pathlib
    import sys as _sys
    _sys.path.insert(0, str(_pathlib.Path(__file__).resolve().parents[1]))

from llm import config


class LLMError(RuntimeError):
    pass


class LLMUnavailable(LLMError):
    """The box is off, unreachable, or not running Ollama."""


@dataclass
class Usage:
    calls: int = 0
    cached: int = 0
    prompt_tokens: int = 0
    eval_tokens: int = 0
    seconds: float = 0.0
    _lock: threading.Lock = field(default_factory=threading.Lock, repr=False)

    def add(self, resp: dict, elapsed: float, cached: bool = False) -> None:
        with self._lock:
            self.calls += 1
            if cached:
                self.cached += 1
                return
            self.prompt_tokens += int(resp.get("prompt_eval_count") or 0)
            self.eval_tokens += int(resp.get("eval_count") or 0)
            self.seconds += elapsed

    def summary(self, wall: float | None = None) -> str:
        """`wall` is real elapsed time. Without it the rate would divide by the
        SUM of per-call times across threads, which understates throughput by
        the concurrency factor -- a 4-way batch looked like 1.8 tok/s when it
        was really running at ~7."""
        live = self.calls - self.cached
        rate = (self.eval_tokens / wall) if wall else 0.0
        per = (wall / live) if wall and live else 0.0
        return (
            f"{self.calls} calls ({self.cached} cached), "
            f"{self.prompt_tokens} prompt + {self.eval_tokens} eval tokens"
            + (f", {rate:.1f} tok/s, {per:.1f}s per item" if wall else "")
        )


def _post(path: str, payload: dict, timeout: float) -> dict:
    req = urllib.request.Request(
        config.OLLAMA_URL.rstrip("/") + path,
        data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(req, timeout=timeout) as fh:
            return json.load(fh)
    except urllib.error.URLError as exc:
        raise LLMUnavailable(f"{config.OLLAMA_URL}{path}: {exc}") from exc


def _get(path: str, timeout: float = 10.0) -> dict:
    try:
        with urllib.request.urlopen(config.OLLAMA_URL.rstrip("/") + path, timeout=timeout) as fh:
            return json.load(fh)
    except urllib.error.URLError as exc:
        raise LLMUnavailable(f"{config.OLLAMA_URL}{path}: {exc}") from exc


class Client:
    def __init__(self, model: str | None = None, use_cache: bool = True):
        self.model = config.MODELS.get(model or "default", model or config.MODELS["default"])
        self.use_cache = use_cache
        self.usage = Usage()
        self._cache_dir = config.CACHE_DIR / hashlib.sha256(self.model.encode()).hexdigest()[:12]

    @property
    def short_name(self) -> str:
        """"gemma:12B" from the full hf.co/... ref, for ledger `source` fields."""
        match = re.search(r"gemma-\d+-([0-9A-Za-z]+)", self.model)
        return f"gemma:{match.group(1)}" if match else self.model

    # -- health -----------------------------------------------------------
    def available_models(self) -> list[str]:
        return [m["name"] for m in _get("/api/tags").get("models", [])]

    def health(self) -> tuple[bool, str]:
        """(ok, message). Never raises -- the box is legitimately off sometimes."""
        try:
            names = self.available_models()
        except LLMUnavailable as exc:
            return False, str(exc)
        if self.model not in names:
            return False, f"model {self.model!r} not installed on the box (have: {len(names)})"
        return True, f"{config.OLLAMA_URL} ok, {len(names)} models"

    def embed_model(self) -> str | None:
        """First installed embedding model, or None. See config.EMBED_MODELS."""
        try:
            names = self.available_models()
        except LLMUnavailable:
            return None
        for want in config.EMBED_MODELS:
            for name in names:
                if name == want or name.startswith(want + ":"):
                    return name
        return None

    def embed(self, inputs: Sequence[str], model: str | None = None) -> list[list[float]] | None:
        """Embeddings, or None when the box has no embedding model installed."""
        model = model or self.embed_model()
        if not model:
            return None
        try:
            resp = _post("/api/embed", {"model": model, "input": list(inputs)}, config.TIMEOUT)
        except LLMUnavailable:
            return None
        return resp.get("embeddings")

    # -- cache ------------------------------------------------------------
    def _cache_key(self, payload: dict, prompt_version: int) -> str:
        blob = json.dumps([payload, prompt_version], sort_keys=True, separators=(",", ":"))
        return hashlib.sha256(blob.encode()).hexdigest()

    def _cache_read(self, key: str) -> dict | None:
        if not self.use_cache:
            return None
        path = self._cache_dir / key[:2] / f"{key}.json"
        if not path.exists():
            return None
        try:
            return json.loads(path.read_text())
        except (OSError, ValueError):
            return None

    def _cache_write(self, key: str, value: dict) -> None:
        if not self.use_cache:
            return
        path = self._cache_dir / key[:2] / f"{key}.json"
        path.parent.mkdir(parents=True, exist_ok=True)
        tmp = path.with_suffix(".tmp")
        tmp.write_text(json.dumps(value))
        tmp.replace(path)

    # -- generation -------------------------------------------------------
    def chat(
        self,
        system: str,
        user: str,
        schema: dict | None = None,
        *,
        prompt_version: int = 1,
        temperature: float = 0.7,
        num_predict: int | None = None,
        num_ctx: int | None = None,
        nonce: int | None = None,
    ) -> dict | str:
        """One structured call. Returns the parsed object when `schema` is given.

        `nonce` is what makes a re-roll possible. Temperature alone cannot do it:
        the disk cache is keyed on the request, so asking the same question twice
        returns the byte-identical cached answer in 0.0s and the sampler is never
        reached. A nonce changes the cache key AND becomes Ollama's `seed`, so
        the second roll is both uncached and genuinely differently sampled.
        """
        payload: dict[str, Any] = {
            "model": self.model,
            "think": False,
            "stream": False,
            "messages": [
                {"role": "system", "content": system},
                {"role": "user", "content": user},
            ],
            "options": {"temperature": temperature},
        }
        if num_predict:
            payload["options"]["num_predict"] = num_predict
        if nonce is not None:
            payload["options"]["seed"] = int(nonce) % (2 ** 31)
        if num_ctx:
            # The box loads this model at 4096. Anything whose prompt grows as it
            # runs must ask for more: on overflow Ollama truncates from the FRONT,
            # which is where the system prompt lives -- so the rules would be
            # dropped silently and only the tail of the request would survive.
            payload["options"]["num_ctx"] = num_ctx
        if schema:
            payload["format"] = schema

        key = self._cache_key(payload, prompt_version)
        hit = self._cache_read(key)
        if hit is not None:
            self.usage.add(hit, 0.0, cached=True)
            return self._parse(hit, schema)

        last: Exception | None = None
        for attempt in range(config.RETRIES):
            started = time.monotonic()
            try:
                resp = _post("/api/chat", payload, config.TIMEOUT)
            except LLMUnavailable:
                raise
            except Exception as exc:  # noqa: BLE001 - retry anything transient
                last = exc
                time.sleep(2 ** attempt)
                continue
            elapsed = time.monotonic() - started
            try:
                parsed = self._parse(resp, schema)
            except LLMError as exc:
                # A malformed structured response is worth one more roll of the
                # dice; caching it would poison every future run.
                last = exc
                continue
            self.usage.add(resp, elapsed)
            self._cache_write(key, resp)
            return parsed
        raise LLMError(f"failed after {config.RETRIES} attempts: {last}")

    @staticmethod
    def _parse(resp: dict, schema: dict | None) -> dict | str:
        content = (resp.get("message") or {}).get("content", "")
        if schema is None:
            return content
        try:
            return json.loads(content)
        except ValueError as exc:
            raise LLMError(f"response was not valid JSON: {content[:200]!r}") from exc

    # -- batching ---------------------------------------------------------
    def map(
        self,
        items: Iterable[Any],
        fn: Callable[[Any], Any],
        concurrency: int | None = None,
        on_error: Callable[[Any, Exception], Any] | None = None,
        on_progress: Callable[[int, int], None] | None = None,
    ) -> list[Any]:
        """Run `fn` over `items` on the pool, preserving input order.

        Errors on a single item never abort the batch -- at 2000 items a lost
        run is expensive, and the cache makes a resume nearly free anyway.
        """
        items = list(items)
        workers = concurrency or config.CONCURRENCY

        def wrapped(item):
            try:
                return fn(item)
            except LLMUnavailable:
                raise
            except Exception as exc:  # noqa: BLE001
                if on_error:
                    return on_error(item, exc)
                return None

        if on_progress is None:
            with ThreadPoolExecutor(max_workers=workers) as pool:
                return list(pool.map(wrapped, items))

        # Same result, in the same order, but reporting as each one lands. A
        # long batch that prints nothing for two hours is indistinguishable
        # from a hung one.
        out: list[Any] = [None] * len(items)
        done = 0
        with ThreadPoolExecutor(max_workers=workers) as pool:
            futures = {pool.submit(wrapped, item): i for i, item in enumerate(items)}
            for future in as_completed(futures):
                out[futures[future]] = future.result()
                done += 1
                on_progress(done, len(items))
        return out

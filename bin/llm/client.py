"""Client for the local LLM box.

Deliberately stdlib-only (urllib + threads) to match the rest of bin/, which
depends on nothing but PyYAML.

**It speaks the OpenAI-compatible API (`/v1/...`), not a server's native one.**
The box ran Ollama until 2026-09-14, a single `llama-server` until 2026-09-15,
and a llama.cpp **router** since; all three implement `/v1/chat/completions` and
`/v1/models`, so one transport serves any of them and a move is a
`config.LLM_URL` edit. What is NOT portable is anything under `/api/` --
`/api/chat`, `/api/tags`, and above all `options.num_ctx`, which is why
`num_ctx` below is advisory here in a way it was not on Ollama.

The router honours the `model` field: it serves every name in `config.MODELS`,
loading one on demand and evicting the one before it (it holds exactly one). So
the model is a genuine per-request choice again, and switching costs a reload on
the far side rather than a restart someone has to go and perform.

Three things every call gets, because they were all needed in practice:
  * thinking off  -- a reasoning model (Qwen3) otherwise emits a `<think>` block
                     that is not valid output; asked off via the chat template,
                     and stripped defensively if one arrives anyway. Only qwen36
                     honours the switch (`config.THINKING_OPTIONAL`); the
                     DeepSeek models always reason, and get a token floor
                     instead (`config.MIN_PREDICT`).
  * a JSON schema -- structured output is honoured (llama.cpp compiles it to a
                     GBNF grammar), so responses are parsed, never scraped out
                     of prose.
  * a disk cache  -- keyed on model+prompt+schema+prompt_version, so re-runs and
                     retries after a crash cost nothing, and editing a prompt
                     invalidates exactly the entries it should.
"""
from __future__ import annotations

import hashlib
import json
import re
import sys
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
    """The box is off, unreachable, or not serving an OpenAI-compatible API.

    Note that the common failure is a HANG, not a refusal: llama-server binds
    127.0.0.1 unless told otherwise, and a firewall on that machine DROPs rather
    than rejects, so both look like a timeout from here. See config.LLM_URL.
    """


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
            usage = resp.get("usage") or {}
            self.prompt_tokens += int(usage.get("prompt_tokens")
                                      or resp.get("prompt_eval_count") or 0)
            self.eval_tokens += int(usage.get("completion_tokens")
                                    or resp.get("eval_count") or 0)
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
        config.LLM_URL.rstrip("/") + path,
        data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(req, timeout=timeout) as fh:
            return json.load(fh)
    except urllib.error.HTTPError as exc:
        # llama-server puts the real complaint in the body ("the request exceeds
        # the available context size", a schema it could not compile); the
        # status line alone is never enough to act on.
        detail = ""
        try:
            detail = exc.read().decode("utf-8", "replace")[:400]
        except Exception:                                  # noqa: BLE001
            pass
        raise LLMError(f"{config.LLM_URL}{path}: {exc}{' -- ' + detail if detail else ''}") from exc
    except urllib.error.URLError as exc:
        raise LLMUnavailable(f"{config.LLM_URL}{path}: {exc}") from exc


def _get(path: str, timeout: float = 10.0) -> dict:
    try:
        with urllib.request.urlopen(config.LLM_URL.rstrip("/") + path, timeout=timeout) as fh:
            return json.load(fh)
    except urllib.error.URLError as exc:
        raise LLMUnavailable(f"{config.LLM_URL}{path}: {exc}") from exc


_UNSET = object()

_THINK_RE = re.compile(r"<think>.*?</think>\s*", re.DOTALL | re.IGNORECASE)


def _ctx_from_args(row: dict) -> int | None:
    """`--ctx-size` out of a router row's launch argv, or None."""
    args = (row.get("status") or {}).get("args") or []
    for flag in ("--ctx-size", "-c"):
        if flag in args:
            try:
                return int(args[args.index(flag) + 1]) or None
            except (IndexError, ValueError):
                return None
    return None


def _strip_think(content: str) -> str:
    """Drop a reasoning block the model emitted anyway.

    `chat_template_kwargs.enable_thinking=False` is the real control, but it
    only works if the model's chat template honours that name -- on this box
    only qwen36 does, and both DeepSeek models ignore it in silence. An
    unstripped block makes the content fail to parse as JSON, which reads as
    "the model is broken".
    """
    return _THINK_RE.sub("", content).strip()


def _wire(payload: dict) -> dict:
    """The payload as sent: local-only keys (leading underscore) removed.

    They exist to take part in the cache key without being fields the server
    would reject -- `_num_ctx_hint` is the one.
    """
    return {k: v for k, v in payload.items() if not k.startswith("_")}


class Client:
    def __init__(self, model: str | None = None, use_cache: bool = True):
        self.model = config.MODELS.get(model or "default", model or config.MODELS["default"])
        self.use_cache = use_cache
        self.timeout = config.timeout_for(self.model)
        self.usage = Usage()
        self._ctx: Any = _UNSET
        self._ctx_warned = False
        self._cache_dir = config.CACHE_DIR / hashlib.sha256(self.model.encode()).hexdigest()[:12]

    @property
    def short_name(self) -> str:
        """A name fit for a ledger `source` field or a sidecar.

        "gemma:12B" from the old hf.co/... refs, so historic ledger entries stay
        greppable; otherwise the model id with any path and .gguf trimmed off,
        which is what a llama-server `--alias` or model filename gives.
        """
        match = re.search(r"gemma-\d+-([0-9A-Za-z]+)", self.model)
        if match:
            return f"gemma:{match.group(1)}"
        name = self.model.rsplit("/", 1)[-1].rsplit("\\", 1)[-1]
        return name[:-5] if name.lower().endswith(".gguf") else name

    # -- health -----------------------------------------------------------
    def available_models(self) -> list[str]:
        """Every model name the box will answer to, loaded or not.

        On the router that is every section of its `models.ini`, all of them
        reported `unloaded` until a request names one -- so a name here is a
        promise the box can serve it, not a claim that it is in memory.
        """
        return [m["id"] for m in _get("/v1/models").get("data", []) if m.get("id")]

    def context_size(self) -> int | None:
        """The served model's context window, or None if the box did not say.

        A bare llama-server reports it in /v1/models as `meta.n_ctx`. The router
        reports no `meta` at all -- an unloaded model has no context yet -- but
        it does publish the argv it would launch with, and `--ctx-size` there is
        the same number one step earlier. Either way it is the value it was
        launched with, not the model's trained maximum, and it is what a
        too-long prompt is rejected against.
        """
        if self._ctx is _UNSET:
            self._ctx = None
            try:
                rows = _get("/v1/models").get("data", [])
                mine = [r for r in rows if r.get("id") == self.model] or rows
                if len(mine) == 1:
                    self._ctx = (int((mine[0].get("meta") or {}).get("n_ctx") or 0)
                                 or _ctx_from_args(mine[0]))
            except (LLMUnavailable, ValueError, TypeError):
                self._ctx = None
        return self._ctx

    def health(self) -> tuple[bool, str]:
        """(ok, message). Never raises -- the box is legitimately off sometimes."""
        try:
            names = self.available_models()
        except LLMUnavailable as exc:
            return False, str(exc)
        if not names:
            return False, f"{config.LLM_URL} answered but serves no model"
        ctx = self.context_size()
        suffix = f", {ctx} ctx" if ctx else ""
        if self.model in names:
            return True, f"{config.LLM_URL} ok, {len(names)} model(s){suffix}"
        if len(names) == 1:
            # A bare llama-server serves the one model it was started with and
            # ignores the `model` field entirely, so there a name mismatch is
            # cosmetic -- but it is still worth saying out loud, because the
            # name is part of every cache key: leave it stale and a new model
            # quietly returns the previous one's cached answers. The router is
            # the other case and falls through below: it takes the name
            # literally, so a wrong one is an error, not a substitution.
            return True, (f"{config.LLM_URL} ok, serving {names[0]!r}{suffix} "
                          f"(config.MODELS says {self.model!r})")
        return False, (f"model {self.model!r} is not one of the {len(names)} "
                       f"this box serves ({', '.join(sorted(names))})")

    def embed_model(self) -> str | None:
        """First served embedding model, or None. See config.EMBED_MODELS."""
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
        """Embeddings, or None when the box serves no embedding model.

        A llama-server needs `--embeddings` and a second server for the
        embedding model, so None is the normal answer here now; every caller
        has a non-embedding fallback path.
        """
        model = model or self.embed_model()
        if not model:
            return None
        try:
            resp = _post("/v1/embeddings", {"model": model, "input": list(inputs)},
                         config.TIMEOUT)
        except LLMError:
            return None
        rows = resp.get("data") or []
        out = [r.get("embedding") for r in rows if r.get("embedding")]
        return out or None

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
        reached. A nonce changes the cache key AND becomes the sampler `seed`, so
        the second roll is both uncached and genuinely differently sampled.

        `num_ctx` is **advisory**. Ollama's `options.num_ctx` grew the context
        per request; llama-server's is fixed at startup by `-c`, with no request
        field that can raise it, so a prompt over that size comes back as an HTTP
        error naming the limit rather than being silently truncated. It is kept
        in the cache key so a caller that asks for a bigger window still gets a
        fresh answer, and it is what the error message quotes back at you.
        """
        payload: dict[str, Any] = {
            "model": self.model,
            "stream": False,
            "messages": [
                {"role": "system", "content": system},
                {"role": "user", "content": user},
            ],
            "temperature": temperature,
            # Qwen3 and friends think by default and put a <think> block in the
            # content, which is not the answer and is not separable from it once
            # a grammar is also in play. This is the chat template's own switch.
            "chat_template_kwargs": {"enable_thinking": False},
        }
        floor = config.MIN_PREDICT.get(self.model, 0)
        if num_predict or floor:
            # The floor is for the models that always reason: they spend the
            # budget thinking and only then write, so too small a max_tokens
            # comes back finish_reason "length" with empty content -- which
            # looks exactly like a broken box. See config.MIN_PREDICT.
            payload["max_tokens"] = max(num_predict or 0, floor)
        if nonce is not None:
            payload["seed"] = int(nonce) % (2 ** 31)
        if num_ctx:
            payload["_num_ctx_hint"] = num_ctx          # cache key only, see above
            served = self.context_size()
            if served and num_ctx > served and not self._ctx_warned:
                # Say it here rather than let the caller read an HTTP 400 out of
                # a retry loop: the fix is on the box (`llama-server -c`), and
                # nothing this process does can raise the window.
                self._ctx_warned = True
                print(f"[warn] caller asked for a {num_ctx}-token context but "
                      f"the box serves {served}; restart llama-server with "
                      f"-c {num_ctx} if this prompt overflows", file=sys.stderr)
        if schema:
            # llama.cpp compiles this to a GBNF grammar, so the answer really is
            # constrained rather than merely requested.
            payload["response_format"] = {
                "type": "json_schema",
                "json_schema": {"name": "response", "schema": schema,
                                "strict": True},
            }

        key = self._cache_key(payload, prompt_version)
        hit = self._cache_read(key)
        if hit is not None:
            self.usage.add(hit, 0.0, cached=True)
            return self._parse(hit, schema)

        last: Exception | None = None
        for attempt in range(config.RETRIES):
            started = time.monotonic()
            try:
                resp = _post("/v1/chat/completions", _wire(payload), self.timeout)
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
        choices = resp.get("choices") or []
        first = choices[0] if choices else {}
        message = (first.get("message") or {}) if choices else {}
        content = _strip_think(message.get("content") or "")
        if not content and message.get("reasoning_content"):
            # The whole budget went into the reasoning block and the answer was
            # never reached. Say so: the raw symptom (empty content, a "length"
            # finish) reads as a broken box, while the fix is a bigger budget --
            # config.MIN_PREDICT, or the caller's num_predict.
            raise LLMError(
                f"the model reasoned for "
                f"{len(message['reasoning_content'])} characters and never "
                f"reached an answer (finish_reason "
                f"{first.get('finish_reason')!r}); raise max_tokens")
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

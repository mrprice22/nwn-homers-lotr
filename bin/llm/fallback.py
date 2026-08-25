"""Claude Sonnet as a per-item fallback when the local model fails.

Gemma drops items: malformed JSON that survives every retry, an empty response,
a context overflow. Round one lost 29 of 944 that way. Rather than leave those
holes, retry the individual item with Claude Sonnet at medium effort.

**Why the `claude` CLI and not the Anthropic SDK.** On this host there is no
`ANTHROPIC_API_KEY`, no `ant` CLI, and the `anthropic` package is not installed --
while `claude` is on PATH and already authenticated. This repo's only third-party
dependency is PyYAML, and making a rare recovery path depend on a new SDK plus a
provisioned API key would be a poor trade. The CLI is the credential the machine
already has.

Tools are disallowed on the call: this is one prose generation, and the agent
harness has no business reading the repository to produce it.

**This spends the user's Claude subscription, not a metered key.** Hence the cap:
a systemic Gemma outage must not quietly push a 900-item batch onto it. On
reaching the cap the fallback switches off and the run says so.
"""
from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import threading

if __package__ in (None, ""):
    import pathlib as _pathlib
    import sys as _sys
    _sys.path.insert(0, str(_pathlib.Path(__file__).resolve().parents[1]))

MODEL = os.environ.get("LLM_FALLBACK_MODEL", "sonnet")
EFFORT = os.environ.get("LLM_FALLBACK_EFFORT", "medium")
TIMEOUT = float(os.environ.get("LLM_FALLBACK_TIMEOUT", "180"))
DEFAULT_CAP = int(os.environ.get("LLM_FALLBACK_MAX", "50"))

# One prose generation; the harness must not go exploring.
NO_TOOLS = "Bash,Read,Write,Edit,Glob,Grep,WebFetch,WebSearch,Task,NotebookEdit"

SOURCE = f"sonnet:{EFFORT}"

_FENCE = re.compile(r"^```(?:json)?\s*|\s*```$", re.S)


class Budget:
    """Thread-safe cap on how many items may fall back in one run."""

    def __init__(self, cap: int = DEFAULT_CAP):
        self.cap = cap
        self.used = 0
        self.exhausted_reported = False
        self._lock = threading.Lock()

    def take(self) -> bool:
        with self._lock:
            if self.used >= self.cap:
                return False
            self.used += 1
            return True

    @property
    def spent(self) -> int:
        with self._lock:
            return self.used


def available() -> bool:
    return shutil.which("claude") is not None


def _extract(text: str) -> dict | str:
    """Parse the CLI's stdout, tolerating a code fence around the JSON."""
    text = text.strip()
    if not text:
        raise ValueError("empty response")
    candidate = _FENCE.sub("", text).strip()
    try:
        return json.loads(candidate)
    except ValueError:
        # A JSON object anywhere in the output is still usable.
        match = re.search(r"\{.*\}", candidate, re.S)
        if match:
            return json.loads(match.group(0))
        return candidate          # schema-less tasks want the raw text


def schema_instruction(schema: dict | None) -> str:
    """Turn a JSON schema into a prompt instruction.

    Ollama enforces structure with its `format` parameter, so the task prompts
    never had to ask for JSON. The CLI has no equivalent, so the first live test
    of this fallback returned perfectly good prose and no JSON at all -- the
    schema has to be stated in words here or nothing downstream can parse it.
    """
    if not schema:
        return ""
    fields = ", ".join(
        f"{name} ({spec.get('type', 'string')})"
        for name, spec in (schema.get("properties") or {}).items()
    )
    return ("\n\nReturn ONLY a single JSON object with these fields: "
            f"{fields}. No text before or after it, and no code fence.")


def chat(system: str, user: str, structured: bool = True,
         schema: dict | None = None) -> dict | str:
    """One Sonnet generation. Raises on failure -- the caller decides what next."""
    if not available():
        raise RuntimeError("`claude` is not on PATH")
    if structured:
        system = system + schema_instruction(schema)
    cmd = ["claude", "-p", "--model", MODEL, "--effort", EFFORT,
           "--disallowed-tools", NO_TOOLS, "--system-prompt", system, user]
    proc = subprocess.run(cmd, capture_output=True, text=True, timeout=TIMEOUT)
    if proc.returncode != 0:
        raise RuntimeError(f"claude exited {proc.returncode}: "
                           f"{(proc.stderr or proc.stdout).strip()[:200]}")
    result = _extract(proc.stdout)
    if structured and not isinstance(result, dict):
        raise ValueError(f"expected JSON, got {str(result)[:120]!r}")
    return result


def try_chat(system: str, user: str, budget: Budget, structured: bool = True,
             schema: dict | None = None) -> tuple[dict | str | None, str | None]:
    """(result, error). Returns (None, reason) rather than raising."""
    if not available():
        return None, "claude not on PATH"
    if not budget.take():
        return None, f"fallback cap reached ({budget.cap})"
    try:
        return chat(system, user, structured, schema), None
    except Exception as exc:  # noqa: BLE001 - a fallback must never be the thing that breaks
        return None, str(exc)[:200]

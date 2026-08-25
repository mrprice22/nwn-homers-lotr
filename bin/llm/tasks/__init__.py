"""Task recipes. One module per task; see base.Task for the contract.

Adding a task is the only thing an agent should ever need to do here, and it is
a fixed shape: selector, context, schema, prompt, validate, apply, risk. Once
written, running the task costs no agent tokens at all.
"""
from __future__ import annotations

import importlib
import pkgutil
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from llm.tasks.base import Task

_SKIP = {"base", "validators"}


def registry() -> dict[str, "Task"]:
    """Every task module exposing a module-level `TASK`."""
    found: dict[str, Task] = {}
    for info in pkgutil.iter_modules(__path__):
        if info.name in _SKIP or info.name.startswith("_"):
            continue
        mod = importlib.import_module(f"{__name__}.{info.name}")
        task = getattr(mod, "TASK", None)
        if task is not None:
            found[task.name] = task
    return found

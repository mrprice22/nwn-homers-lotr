"""Server side of the roadmap editor's "LLM Changes" review panel.

Kept out of bin/roadmap-editor.py because that file is already 4800 lines, and
because nothing here touches roadmap.yaml -- so the editor can serve it outside
the 60s yaml_lock, exactly as it already does for /api/palette/refresh.

The panel answers one question: *of everything a model wrote into this repo,
what should a human actually look at?* Ordering is by the priority score the
task recipe computed at generation time (validator warnings, near-duplicate
score, self-reported confidence) -- never by re-asking a model.
"""
from __future__ import annotations

import time
from typing import Any

if __package__ in (None, ""):
    import pathlib as _pathlib
    import sys as _sys
    _sys.path.insert(0, str(_pathlib.Path(__file__).resolve().parents[1]))

from llm import config, gff, ledger

try:
    from llm import itemstats
except Exception:  # noqa: BLE001 - the panel must render without the wiki index
    itemstats = None

# Ordered worst-first; the panel renders them as sections in this order.
RISK_ORDER = {"hold": 0, "review": 1, "auto": 2}

# Which ledger field holds which half of an item's description. Compare mode
# pairs them so both are judged against the same stat block.
UNIDENTIFIED = "Description.value.0"
IDENTIFIED = "DescIdentified.value.0"

_BRIEF_CACHE: dict[str, dict | None] = {}


def _resref(path: str) -> str:
    name = path.rsplit("/", 1)[-1]
    return name[:-9] if name.endswith(".uti.json") else ""


def item_stats(path: str) -> dict | None:
    """The item's stat block for a changed file, or None if not an item.

    Reviewing prose about an object without seeing the object is guesswork --
    this is what makes "does the register match the thing" answerable. Uses the
    same itemstats.item_brief() the prompt was built from, so the panel and the
    generator cannot drift.
    """
    if itemstats is None:
        return None
    resref = _resref(path)
    if not resref:
        return None
    if resref not in _BRIEF_CACHE:
        try:
            _BRIEF_CACHE[resref] = itemstats.item_brief(resref)
        except Exception:  # noqa: BLE001
            _BRIEF_CACHE[resref] = None
    return _BRIEF_CACHE[resref]


def payload(show_done: bool = False, task: str = "", limit: int = 400) -> dict[str, Any]:
    """Everything the panel needs in one GET."""
    records = ledger.read_all()
    if task:
        records = [r for r in records if r.get("task") == task]

    pending = [r for r in records if r.get("review") == "pending"]
    visible = records if show_done else pending
    visible.sort(key=lambda r: (RISK_ORDER.get(r.get("risk"), 9),
                                -float(r.get("priority") or 0),
                                r.get("file", "")))

    groups: dict[str, dict] = {}
    for rec in visible[:limit]:
        key = f"{rec.get('task')}|{rec.get('risk')}|{rec.get('batch')}"
        group = groups.setdefault(key, {
            "key": key,
            "task": rec.get("task"),
            "risk": rec.get("risk"),
            "batch": rec.get("batch"),
            "source": rec.get("source"),
            "ts": rec.get("ts"),
            "rows": [],
        })
        group["rows"].append({
            "id": rec.get("id"),
            "file": rec.get("file"),
            "field": rec.get("field"),
            "before": rec.get("before"),
            "after": rec.get("after"),
            "review": rec.get("review"),
            "priority": rec.get("priority"),
            "warnings": rec.get("warnings") or [],
            "confidence": rec.get("confidence"),
            "source": rec.get("source"),
            "commit": rec.get("commit"),
            "item": item_stats(rec.get("file", "")),
        })

    for group in groups.values():
        group["count"] = len(group["rows"])
        group["flagged"] = sum(1 for r in group["rows"] if r["warnings"])
        # Name every model that contributed, with counts when more than one did.
        # The header used to show the first record's source, which would report a
        # batch containing Sonnet recoveries as pure Gemma.
        tally: dict[str, int] = {}
        for r in group["rows"]:
            tally[r.get("source") or "unknown"] = tally.get(r.get("source") or "unknown", 0) + 1
        group["sources"] = (next(iter(tally)) if len(tally) == 1 else
                            ", ".join(f"{k} x{v}" for k, v in
                                      sorted(tally.items(), key=lambda kv: -kv[1])))

    return {
        "groups": sorted(groups.values(),
                         key=lambda g: (RISK_ORDER.get(g["risk"], 9), g["batch"]), reverse=False),
        "batches": ledger.summary(),
        "tasks": sorted({r.get("task") for r in records if r.get("task")}),
        "total": len(records),
        "pending": len(pending),
        "shown": min(len(visible), limit),
        "truncated": len(visible) > limit,
    }


def compare_payload(show_done: bool = False, limit: int = 200) -> dict[str, Any]:
    """One row per ITEM, pairing its unidentified and identified text.

    The default view groups by batch, which is right for auditing one run but
    wrong for judging an item: the two halves of its description were written in
    different runs and only make sense read together, against the same stats.
    """
    # Current text comes from DISK, not from the ledger. The ledger is a history:
    # after the round-one text was moved to the unidentified slot, its original
    # record still says field=DescIdentified, and trusting that showed the same
    # sentence in both columns. The file is the only thing that knows what an
    # item actually says now.
    # "Newest" must be decided by TIMESTAMP, not by the order read_all() yields.
    # Batches sort newest-first, but records *within* a file keep append order --
    # so two re-rolls of the same item on the same day land in one file and the
    # OLDER one was being picked. Its text no longer matched disk, the row was
    # reported as "edited outside the panel", and its buttons disappeared.
    latest: dict[tuple[str, str], dict] = {}
    for order, rec in enumerate(ledger.read_all()):
        field = rec.get("field")
        if field not in (UNIDENTIFIED, IDENTIFIED):
            continue
        key = (rec.get("file", ""), field)
        stamp = (rec.get("ts") or "", -order)
        if key not in latest or stamp > latest[key][0]:
            latest[key] = (stamp, rec)
    latest = {k: v[1] for k, v in latest.items()}

    items: dict[str, dict] = {}
    for path in sorted({f for f, _ in latest}):
        try:
            data = gff.load(config.REPO / path)
        except (OSError, ValueError):
            continue
        row = {"file": path, "item": item_stats(path),
               "unidentified": None, "identified": None}
        for field, slot in ((UNIDENTIFIED, "unidentified"), (IDENTIFIED, "identified")):
            text = gff.read_path(data, field)
            if not text:
                continue
            rec = latest.get((path, field)) or {}
            # Only attribute the text to a ledger record if it still matches;
            # otherwise a human edited it outside the panel.
            matched = rec.get("after") == text
            row[slot] = {
                "id": rec.get("id") if matched else None,
                "file": path,
                "field": field,
                "text": text,
                "review": rec.get("review", "pending") if matched else "edited outside",
                "source": rec.get("source") if matched else "human",
                "task": rec.get("task") if matched else None,
                "warnings": (rec.get("warnings") or []) if matched else [],
                "confidence": rec.get("confidence") if matched else None,
                "priority": (rec.get("priority") or 0) if matched else 0,
            }
        if row["unidentified"] or row["identified"]:
            items[path] = row

    rows = list(items.values())
    if not show_done:
        rows = [r for r in rows
                if (r["unidentified"] and r["unidentified"]["review"] == "pending")
                or (r["identified"] and r["identified"]["review"] == "pending")]

    def sort_key(row):
        halves = [h for h in (row["unidentified"], row["identified"]) if h]
        return (-max((h["priority"] for h in halves), default=0), row["file"])

    rows.sort(key=sort_key)
    return {
        "mode": "compare",
        "rows": rows[:limit],
        "total": len(items),
        "shown": min(len(rows), limit),
        "truncated": len(rows) > limit,
        "pending": sum(1 for r in items.values()
                       if (r["unidentified"] and r["unidentified"]["review"] == "pending")
                       or (r["identified"] and r["identified"]["review"] == "pending")),
        "tasks": [],
        "groups": [],
        "batches": ledger.summary(),
    }


def reroll(change_id: str | None = None, engine: str = "gemma",
           file: str | None = None, field: str | None = None) -> dict[str, Any]:
    """Generate a fresh description for one item and write it in place.

    Two things make this work at all:

    * A **nonce**. The response cache is keyed on the request, so re-asking the
      same question returns the byte-identical answer in 0.0s -- temperature is
      already 0.9 and never gets a say. The nonce changes the cache key and
      becomes Ollama's `seed`, so the roll is uncached and differently sampled.
    * **Task.item_builder**. The selector deliberately skips items whose field is
      already filled, which by definition is every item you would want to re-roll.

    The previous text is recorded as `before`, so a re-roll is revertible like
    any other change -- and re-rolling twice still walks back to the original.
    """
    import random

    from llm.client import Client, LLMError, LLMUnavailable
    from llm.tasks import registry

    if change_id:
        found = ledger.find(change_id)
        if not found:
            return {"ok": False, "message": f"no ledger record {change_id!r}"}
        _, rec = found
    elif file and field:
        # Text with no ledger record is still re-rollable -- a hand edit should
        # not strand an item.
        rec = {"file": file, "field": field, "task": None, "batch": None}
    else:
        return {"ok": False, "message": "re-roll needs a change id, or a file and field"}

    # Resolve by FIELD first. The newest record for the unidentified slot is the
    # migration that moved round-one text into it, and `desc_to_unidentified` is
    # a relocation script, not a generator -- looking the task up by name found
    # nothing and the button simply failed.
    tasks = registry()
    task = next((x for x in tasks.values() if x.field and x.field == rec.get("field")),
                None) or tasks.get(rec.get("task"))
    if task is None:
        return {"ok": False,
                "message": f"nothing knows how to regenerate {rec.get('field')!r}"}
    if task.item_builder is None:
        return {"ok": False,
                "message": f"{task.name} does not support re-rolling"}

    resref = _resref(rec.get("file", ""))
    item = task.item_builder(resref)
    if item is None:
        return {"ok": False, "message": f"could not rebuild the prompt for {resref}"}

    target = config.REPO / rec["file"]
    current = gff.read_path(gff.load(target), rec["field"])
    nonce = random.randrange(1 << 30)

    if engine == "sonnet":
        from llm import fallback
        if not fallback.available():
            return {"ok": False, "message": "`claude` is not on PATH"}
        budget = fallback.Budget(cap=1)
        raw, error = fallback.try_chat(task.system, task.user_prompt(item), budget,
                                       structured=task.schema is not None,
                                       schema=task.schema)
        if raw is None:
            return {"ok": False, "message": f"sonnet: {error}"}
        source = fallback.SOURCE
    else:
        client = Client(task.model)
        try:
            raw = client.chat(task.system, task.user_prompt(item), task.schema,
                              prompt_version=task.prompt_version,
                              temperature=max(task.temperature, 0.95),
                              nonce=nonce)
        except LLMUnavailable as exc:
            return {"ok": False, "message": f"gemma box unavailable: {exc}"}
        except LLMError as exc:
            return {"ok": False, "message": f"gemma: {exc}"}
        source = client.short_name

    text, confidence = task.parse(raw)
    cleaned, warnings = task.validate(text, item)
    if not cleaned:
        return {"ok": False, "message": f"{engine} returned nothing usable"}
    if cleaned == current:
        return {"ok": False,
                "message": "the re-roll came back identical -- try again"}

    data = gff.load(target)
    gff.write_path(data, rec["field"], cleaned)
    gff.dump(target, data)

    # Re-rolls go in their own dated batch, never appended to the original.
    # read_all() sorts batches newest-first but records within a file stay in
    # append order, so a re-roll written back into its source batch would sort
    # as if it were older than the text it replaced.
    batch = f"reroll-{time.strftime('%Y%m%d')}"
    change = ledger.Change(
        file=rec["file"], field=rec["field"], before=current, after=cleaned,
        task=task.name, risk=task.risk, batch=batch,
        source=f"{source} (re-roll)", review="pending",
        warnings=warnings, confidence=confidence,
        prompt_version=task.prompt_version,
        note=f"re-rolled by {engine}",
    )
    ledger.Ledger(batch).append(change)
    return {"ok": True, "message": f"re-rolled with {source}.", "text": cleaned,
            "warnings": warnings, "id": change.id}


def adopt(path: str, field: str) -> dict[str, Any]:
    """Take the text currently on disk under ledger management.

    Some text has no ledger record: a hand edit outside the panel, a field
    written before the harness existed, or a record whose text has since been
    superseded. Without this there is no way to *keep* such text -- it cannot be
    approved, because approval marks a record and there is none.

    Adopting writes a record whose `before` equals its `after`, so the entry is
    an assertion that this text is wanted. Reverting it is therefore a no-op on
    disk, which is correct: there is no earlier generated version to go back to.
    """
    target = config.REPO / path
    if not target.exists():
        return {"ok": False, "message": f"no such file: {path}"}
    text = gff.read_path(gff.load(target), field)
    if not text:
        return {"ok": False, "message": "there is no text in that field to adopt"}

    existing = next((r for r in ledger.read_all()
                     if r.get("file") == path and r.get("field") == field
                     and r.get("after") == text), None)
    if existing:
        ledger.approve(existing["id"])
        return {"ok": True, "message": "That text already had a record; approved it."}

    batch = f"adopted-{time.strftime('%Y%m%d')}"
    change = ledger.Change(
        file=path, field=field, before=text, after=text,
        task="adopted", risk="auto", batch=batch, source="human",
        review="approved", prompt_version=0,
        note="adopted from disk -- kept as-is",
    )
    ledger.Ledger(batch).append(change)
    return {"ok": True, "message": "Kept. It is now recorded and approved."}


def act(body: dict[str, Any]) -> dict[str, Any]:
    """Apply one panel action. Returns {ok, message} plus a fresh payload."""
    action = body.get("action")
    try:
        if action == "approve":
            ledger.approve(body["id"])
            message = "Approved."
        elif action == "approve_group":
            ids = list(body.get("ids") or [])
            count = ledger.approve_many(ids)
            message = f"Approved {count} changes."
        elif action == "revert":
            rec = ledger.revert(body["id"])
            message = f"Reverted {rec['file']} to its previous value."
        elif action == "edit":
            text = body.get("text")
            if not isinstance(text, str) or not text.strip():
                return {"ok": False, "message": "Edited text cannot be empty. "
                                                "Use Revert to remove it instead."}
            rec = ledger.edit(body["id"], text.strip())
            message = f"Saved your text into {rec['file']}."
        elif action == "adopt":
            result = adopt(body["file"], body["field"])
            if not result.get("ok"):
                return result
            message = result["message"]
        elif action == "reroll":
            result = reroll(body.get("id"), body.get("engine") or "gemma",
                            body.get("file"), body.get("field"))
            if not result.get("ok"):
                return result
            message = result["message"]
        else:
            return {"ok": False, "message": f"unknown action {action!r}"}
    except KeyError as exc:
        return {"ok": False, "message": str(exc)}
    except OSError as exc:
        return {"ok": False, "message": f"could not write the file: {exc}"}

    if body.get("mode") == "compare":
        result = compare_payload(show_done=bool(body.get("show_done")))
    else:
        result = payload(show_done=bool(body.get("show_done")),
                         task=body.get("task") or "")
    result.update({"ok": True, "message": message})
    return result


def available() -> bool:
    return config.LEDGER_DIR.exists() and any(config.LEDGER_DIR.glob("*.jsonl"))

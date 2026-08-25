"""Where an item's properties sit in this module's own distribution.

The problem this solves: a model has no idea that Strength +12 is the ceiling in
this world and Strength +1 is near the floor. Told only "+12", it writes the same
register for a legendary bracer as for a trinket -- which is exactly what round
one of item_desc did.

So: parse every item's resolved property list, build a distribution per
(property, subtype) key across the whole module, and express each of an item's
values as its percentile within its own key. Strength is ranked against Strength,
not against AC or gold.

Gold value is deliberately secondary and never quantified. The item with the best
negative resistance in the game may be enormously desirable and nowhere near the
top by price, so per-property rank leads and gold only bucketises.

Everything here is derived from `docs/` and `module-index/`, both already built.
"""
from __future__ import annotations

import bisect
import json
import re
import time
from collections import defaultdict
from typing import Any

if __package__ in (None, ""):
    import pathlib as _pathlib
    import sys as _sys
    _sys.path.insert(0, str(_pathlib.Path(__file__).resolve().parents[1]))

from llm import config, wiki

CACHE = config.CACHE_DIR / "item_property_stats.json"

NUM = re.compile(r"([+-]?\d+(?:\.\d+)?)")

# Bump when the parsing changes, so a stale cache is rebuilt rather than silently
# serving percentiles computed by the old rules.
VERSION = 2

DICE = re.compile(r"\b(\d+)d(\d+)\b")
# Damage Reduction reads "+5 Soak10": the +5 is the enhancement bonus needed to
# BYPASS it, the Soak10 is how much damage it actually stops. Ranking the first
# number ranks the wrong axis entirely.
SOAK = re.compile(r"Soak\s*(\d+)", re.I)

# A percentile over a handful of samples is noise dressed as a measurement.
# Measured case: "Cast Spell: Harm 1/Day" had n=3, which produced a confident
# "modest" that meant nothing at all.
MIN_SAMPLES = 12

# Properties whose number is a RATE or a flag, not a magnitude. Ranking these
# ranks the wrong axis -- for Cast Spell the number is uses per day, while the
# power is in the spell's name (Harm vs Cloudkill). Detected by value shape
# rather than a hand-kept list, so a new rate-shaped property cannot silently
# start being mis-ranked.
RATE_SHAPED = re.compile(r"/\s*Day|Unlimited|Charges|Uses\s*/", re.I)

# Percentile -> phrase. Words, not numbers: the model is being given a sense of
# scale, and "83rd percentile" is not one.
BANDS = (
    (0.99, "nothing in the world grants more"),
    (0.90, "among the very greatest of its kind"),
    (0.70, "strong"),
    (0.40, "typical"),
    (0.15, "modest"),
    (0.00, "slight"),
)

GOLD_BANDS = (
    (0.98, "artifact-tier"),
    (0.90, "epic-tier"),
    (0.70, "rare"),
    (0.40, "fine"),
    (0.15, "common"),
    (0.00, "mundane"),
)

_CACHED: dict[str, Any] | None = None


# -- parsing ---------------------------------------------------------------
def split_properties(text: str):
    """Yield (whole_chunk, property_name, remainder) for a resolved list."""
    for chunk in (text or "").split(";"):
        chunk = chunk.strip()
        if not chunk:
            continue
        if ":" in chunk:
            name, _, rest = chunk.partition(":")
        else:
            name, rest = chunk, ""
        yield chunk, name.strip(), rest.strip()


def parse_value(name: str, rest: str) -> tuple[str, float, str] | None:
    """(subtype, magnitude, unit) for a rankable property, else None.

    `unit` is "flat" or "dice" and is part of the distribution key, because the
    two are not comparable. Massive Criticals holds 307 dice values against 85
    flat ones; averaged together, a flat 5 outranked 2d6 and 2d12 -- the best in
    the game -- landed in the same band as a flat 10.

    Which number counts as the magnitude depends on the property's shape:
      Ability Bonus: Strength +12  -> 12    the number after the subtype
      Massive Criticals: 2d12      -> 13    the dice MEAN, not the dice count
      Damage Reduction: +5 Soak10  -> 10    the soak, not the bypass threshold
    """
    if RATE_SHAPED.search(rest):
        return None

    # Damage Reduction: rank what it stops, not what defeats it.
    if name == "Damage Reduction":
        soak = SOAK.search(rest)
        return ("-", float(soak.group(1)), "flat") if soak else None

    dice = DICE.search(rest)
    if dice:
        count, faces = int(dice.group(1)), int(dice.group(2))
        subtype = rest[: dice.start()].strip() or "-"
        return subtype, count * (faces + 1) / 2, "dice"

    match = NUM.search(rest)
    if not match:
        return None
    return rest[: match.start()].strip() or "-", float(match.group(1)), "flat"


# -- distributions ---------------------------------------------------------
_ITEMS: list[dict] | None = None
_BY_RESREF: dict[str, dict] | None = None


def _items() -> list[dict]:
    """The item index, parsed once per process.

    Re-reading it per call is a 5,000-entry JSON parse, and item_brief() runs
    once per item -- which made the panel's 915-row compare view quadratic.
    """
    global _ITEMS, _BY_RESREF
    if _ITEMS is not None:
        return _ITEMS
    path = config.MODULE_INDEX / "item_index.json"
    if not path.exists():
        raise SystemExit(
            f"{path} is missing. It is gitignored and built by the wiki refresh;\n"
            "run `nwn-manager wiki` once before using this."
        )
    _ITEMS = json.loads(path.read_text())["items"]
    _BY_RESREF = {i["resref"]: i for i in _ITEMS}
    return _ITEMS


def _entry(resref: str) -> dict:
    _items()
    return (_BY_RESREF or {}).get(resref, {})


def build(force: bool = False) -> dict[str, Any]:
    """Scan every item's wiki page and build the distributions. ~30s."""
    values: dict[str, list[float]] = defaultdict(list)
    golds: list[float] = []
    scanned = 0
    for item in _items():
        cost = item.get("cost_gp")
        if cost:
            golds.append(float(cost))
        text = wiki.item_properties(item["resref"])
        if not text:
            continue
        scanned += 1
        for _, name, rest in split_properties(text):
            parsed = parse_value(name, rest)
            if parsed:
                subtype, magnitude, unit = parsed
                values[f"{name}\x1f{subtype}\x1f{unit}"].append(magnitude)

    data = {
        "version": VERSION,
        "built": time.strftime("%Y-%m-%dT%H:%M:%S"),
        "items_scanned": scanned,
        "properties": {k: sorted(v) for k, v in values.items()},
        "gold": sorted(golds),
    }
    CACHE.parent.mkdir(parents=True, exist_ok=True)
    CACHE.write_text(json.dumps(data))
    return data


def distributions(force: bool = False) -> dict[str, Any]:
    global _CACHED
    if _CACHED is not None and not force:
        return _CACHED
    if CACHE.exists() and not force:
        try:
            cached = json.loads(CACHE.read_text())
            if cached.get("version") == VERSION:
                _CACHED = cached
                return _CACHED
            # Parsing rules changed; percentiles from the old ones are wrong.
        except (OSError, ValueError):
            pass
    _CACHED = build()
    return _CACHED


# -- ranking ---------------------------------------------------------------
def _band(pct: float, bands=BANDS) -> str:
    for threshold, phrase in bands:
        if pct >= threshold:
            return phrase
    return bands[-1][1]


def rank(name: str, subtype: str, value: float,
         unit: str = "flat") -> tuple[float, str] | None:
    """(percentile, phrase) for one property value, or None when unrankable."""
    series = distributions()["properties"].get(f"{name}\x1f{subtype}\x1f{unit}")
    if not series or len(series) < MIN_SAMPLES:
        return None
    pct = bisect.bisect_right(series, value) / len(series)
    return pct, _band(pct)


def gold_tier(cost_gp: float | None) -> tuple[float, str]:
    """(percentile, category). Never exposes the number itself."""
    series = distributions()["gold"]
    if not cost_gp or not series:
        return 0.0, "mundane"
    pct = bisect.bisect_right(series, float(cost_gp)) / len(series)
    return pct, _band(pct, GOLD_BANDS)


# -- the shared context blob ----------------------------------------------
def item_brief(resref: str, entry: dict | None = None) -> dict[str, Any]:
    """Everything both the prompt and the review panel need about one item.

    One function so the two can never disagree about what an item is.
    """
    if entry is None:
        entry = _entry(resref)

    lines: list[str] = []
    best = 0.0
    for chunk, name, rest in split_properties(wiki.item_properties(resref)):
        parsed = parse_value(name, rest)
        ranked = rank(name, *parsed) if parsed else None  # (subtype, value, unit)
        if ranked:
            pct, phrase = ranked
            best = max(best, pct)
            lines.append(f"{chunk} -- {phrase}")
        else:
            lines.append(chunk)

    gold_pct, gold_name = gold_tier(entry.get("cost_gp"))
    overall_pct = max(best, gold_pct)
    return {
        "resref": resref,
        "name": (entry.get("name") or "").strip(),
        "base_item": entry.get("base_item", ""),
        "wiki_url": entry.get("wiki_url", ""),
        "gold_tier": gold_name,
        "overall_tier": _band(overall_pct, GOLD_BANDS),
        "best_property_percentile": round(best, 3),
        "properties": lines,
        "sources": entry.get("sources") or [],
    }


def brief_text(brief: dict[str, Any]) -> str:
    """The prompt-facing rendering of item_brief()."""
    out = [f"Item name: {brief['name']}",
           f"Item type: {brief['base_item'] or 'unknown'}",
           f"Standing in the world: {brief['overall_tier']} "
           f"(value alone: {brief['gold_tier']})"]
    if brief["properties"]:
        out.append("Magical properties, each with how it ranks among all items "
                   "of its kind in this world:")
        out.extend(f"  {line}" for line in brief["properties"])
    if brief["sources"]:
        out.append("Found in the world: " + "; ".join(brief["sources"][:3]))
    return "\n".join(out)


def main(argv: list[str] | None = None) -> int:
    import argparse

    ap = argparse.ArgumentParser(description="Inspect the item property distributions.")
    ap.add_argument("resref", nargs="?", help="show one item's brief")
    ap.add_argument("--rebuild", action="store_true")
    ap.add_argument("--top", type=int, default=0, help="show the N largest distributions")
    args = ap.parse_args(argv)

    data = distributions(force=args.rebuild)
    props = data["properties"]
    print(f"built {data['built']} from {data['items_scanned']} items, "
          f"{len(props)} distributions "
          f"({sum(1 for v in props.values() if len(v) >= MIN_SAMPLES)} rankable "
          f"at n>={MIN_SAMPLES})")

    if args.top:
        for key, series in sorted(props.items(), key=lambda kv: -len(kv[1]))[:args.top]:
            name, sub, unit = key.split("\x1f")
            sub = f"{sub} [{unit}]"
            print(f"  {name} / {sub:<24} n={len(series):<5} "
                  f"min={series[0]:<6} med={series[len(series)//2]:<6} max={series[-1]}")
    if args.resref:
        print()
        print(brief_text(item_brief(args.resref)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

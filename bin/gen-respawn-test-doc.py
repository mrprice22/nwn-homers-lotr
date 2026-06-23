#!/usr/bin/env python3
"""Generate the player-facing respawn-override test script.

Reads the manifest written by bin/split-divergent-creatures.py
(module-index/respawn_override_blueprints.json) plus area names from
unpacked/*.are.json, and writes TESTING-respawn-overrides.md — a per-area
checklist testers can use to confirm every fixed creature respawns with its
correct identity (name / faction / gear) instead of reverting to its blueprint.

Re-run after bin/split-divergent-creatures.py:
    python3 bin/gen-respawn-test-doc.py
"""

import json
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
UNPACKED = os.path.join(ROOT, "unpacked")
MANIFEST = os.path.join(ROOT, "module-index", "respawn_override_blueprints.json")
OUT = os.path.join(ROOT, "TESTING-respawn-overrides.md")

# Hand-picked headline cases (resref of the baked blueprint) shown up top.
HEADLINE = ["cultmember002_3", "archerofmordor_2"]


def fld(s, k):
    v = s.get(k) if isinstance(s, dict) else None
    return v.get("value") if isinstance(v, dict) else None


_COLOR_RE = re.compile(r"<c...>|</c>", re.S)


def _clean(s):
    """Strip NWN <cXYZ>…</c> colour tokens and control chars."""
    s = _COLOR_RE.sub("", s or "")
    return "".join(ch for ch in s if ch >= " ").strip()


def area_name(resref):
    p = os.path.join(UNPACKED, f"{resref}.are.json")
    if not os.path.exists(p):
        return resref
    d = json.load(open(p, encoding="utf-8"))
    nm = fld(d, "Name")
    if isinstance(nm, dict):
        nm = nm.get("0")
    return _clean(nm) or resref


def blueprint(resref):
    p = os.path.join(UNPACKED, f"{resref}.utc.json")
    return json.load(open(p, encoding="utf-8")) if os.path.exists(p) else None


def _name_of(bp):
    first = (fld(bp, "FirstName") or "")
    last = (fld(bp, "LastName") or "")
    if isinstance(fld(bp, "FirstName"), dict):  # cexolocstring already unwrapped by fld
        pass
    f = first.get("0") if isinstance(first, dict) else first
    return (f or "").strip()


def diverge_label(entry):
    """Short 'what changed vs the generic blueprint' note for testers."""
    baked = blueprint(entry["resref"])
    base = blueprint(entry["base"])
    if base is None:                     # stock blueprint — can't diff baseline
        return "name / identity"
    bits = []
    bf = fld(baked, "FirstName")
    bsf = fld(base, "FirstName")
    bf = bf.get("0") if isinstance(bf, dict) else bf
    bsf = bsf.get("0") if isinstance(bsf, dict) else bsf
    if (bf or "") != (bsf or ""):
        bits.append("name")
    if fld(baked, "FactionID") != fld(base, "FactionID"):
        bits.append("**faction/hostility**")
    return ", ".join(bits) if bits else "stats/gear"


def main():
    man = json.load(open(MANIFEST, encoding="utf-8"))
    blueprints = man["blueprints"]
    by_resref = {b["resref"]: b for b in blueprints}

    # area_resref -> list of (display_name, what_changed). Skip generic
    # "(unnamed)" placements — testers can't identify them and they look
    # identical to the stock creature anyway.
    by_area = {}
    named = 0
    skipped = 0
    for b in blueprints:
        if b["name"] == "(unnamed)":
            skipped += 1
            continue
        named += 1
        label = diverge_label(b)
        for a in b["areas"]:
            by_area.setdefault(a, []).append((b["name"], label))

    lines = []
    lines.append("# Respawn-override validation — tester checklist\n")
    lines.append(
        "We fixed a bug where many named/special NPCs **reverted to a generic "
        "version after they died and respawned** (≈15 min). For example, Carn "
        "Dum City's *Numanan Numerocks Second Hand* used to come back as *Numarok "
        "The Black Hand*, and some hostile bosses came back **friendly**. Each "
        "such NPC now has its own blueprint so it respawns exactly as placed.\n")
    lines.append("## How to test each NPC\n")
    lines.append("1. Go to the area and find the NPC. Note its **name**, whether "
                 "it's **hostile/friendly**, and any visible **gear**.\n"
                 "2. Kill it.\n"
                 "3. Wait for it to respawn (about **15 minutes** real time — a DM "
                 "can shorten this for a test session).\n"
                 "4. Confirm the respawn is **identical**: same name, same "
                 "hostility/faction, same equipment. If it comes back with a "
                 "different (generic) name, wrong hostility, or missing gear, "
                 "note the NPC + area and report it.\n")

    lines.append("## Headline cases (check these first)\n")
    for rr in HEADLINE:
        b = by_resref.get(rr)
        if not b:
            continue
        areas = ", ".join(area_name(a) for a in b["areas"])
        lines.append(f"- **{b['name']}** — {areas}. "
                     + ("Used to respawn as a different name."
                        if rr == "cultmember002_3"
                        else "Hostile NPC that must **not** respawn friendly."))
    lines.append("")

    lines.append("## Full checklist by area\n")
    lines.append(f"{named} named NPCs across {len(by_area)} areas. "
                 "Tick each once its respawn matches. "
                 f"({len(blueprints)} total placements were fixed; {skipped} "
                 "generic/unnamed ones are omitted here — nothing to eyeball.)\n")
    for area in sorted(by_area, key=lambda a: area_name(a).lower()):
        rows = sorted(set(by_area[area]))
        lines.append(f"### {area_name(area)}\n")
        lines.append("| ✓ | NPC | Must match on respawn |")
        lines.append("|---|-----|-----------------------|")
        for name, label in rows:
            lines.append(f"| ☐ | {name} | {label} |")
        lines.append("")

    with open(OUT, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))
    print(f"[gen-respawn-test-doc] wrote {OUT} "
          f"({named} named NPCs across {len(by_area)} areas; "
          f"{skipped} unnamed omitted)")


if __name__ == "__main__":
    main()

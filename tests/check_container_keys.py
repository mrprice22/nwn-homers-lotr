#!/usr/bin/env python3
"""Build gate: every locked, keyed container must have an obtainable key.

A placeable container that is Locked with a KeyName, but whose key item has no
source, is a soft-bricked chest: players who can't pick it (high OpenLockDC / a
KeyRequired lock) can never open it, and admins can't find the key in the
toolset. This is exactly the numenor-chests bug -- the three Setti coffers in
Numenor: Noirinan were keyed to SettiBeltKey/SettiRingKey/SettiShieldKey, none of
which existed as an item.

A key is considered SATISFIED when either:
  * a `.uti` blueprint exists whose Tag equals the KeyName, OR
  * some `.nss` script mentions the key name (scripts mint keys by resref, e.g.
    annu_key does CreateItemOnObject("annuminaskey", ...)).
The second rule keeps runtime-minted keys (housing/inn/quest keys) from being
false-flagged.

Scope: placeable CONTAINERS only (`*.utp.json` blueprints + the Placeable List
of every `*.git.json`). Doors are out of scope -- most door keys in this module
are minted at runtime.

KNOWN baseline: a small allow-list of pre-existing offenders that are tracked but
deliberately not fixed yet (see the numenor-chests roadmap notes). They are
reported every run but do NOT fail the build, so the gate stays green while still
catching any NEW missing-key container as a regression.

Reads unpacked/ directly -- no dependency on module-index/ (gitignored).
Exits 0 when only KNOWN entries remain, 1 on any new/unlisted offender.
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
UNPACKED = ROOT / "unpacked"

# Pre-existing, tracked-but-unfixed offenders: (area-or-blueprint stem, chest tag).
# Keep in sync with the numenor-chests roadmap item's "other containers" report.
KNOWN = {
    ("diviningpl", "DiviningPool"),      # utp blueprint, KeyRequired, key 'divinekey'
    ("loogazlair", "Chest1"),            # git instance, key 'loogazkey', pickable DC18
    ("loogazlair", "Chest2"),
}


def gv(node):
    return node["value"] if isinstance(node, dict) and "value" in node else node


def item_tags() -> set[str]:
    tags = set()
    for f in UNPACKED.glob("*.uti.json"):
        try:
            d = json.loads(f.read_text())
        except (json.JSONDecodeError, OSError):
            continue
        t = gv(d.get("Tag"))
        if t:
            tags.add(t)
    return tags


def script_blob() -> str:
    """All script source concatenated, lowercased, for key-name lookups."""
    parts = []
    for f in UNPACKED.glob("*.nss"):
        try:
            parts.append(f.read_text(errors="ignore"))
        except OSError:
            pass
    return "\n".join(parts).lower()


def key_satisfied(key: str, tags: set[str], scripts: str) -> bool:
    if key in tags:
        return True
    # word-boundary match so 'loogazkey' doesn't match a longer unrelated token
    return re.search(r"\b" + re.escape(key.lower()) + r"\b", scripts) is not None


def locked_keyed(p: dict):
    """Return (tag, key) if p is a locked container with a KeyName, else None."""
    key = gv(p.get("KeyName"))
    locked = gv(p.get("Locked"))
    if key and locked:
        return gv(p.get("Tag")), key
    return None


def main() -> int:
    tags = item_tags()
    scripts = script_blob()

    offenders = []  # (stem, tag, key)

    for f in UNPACKED.glob("*.utp.json"):
        try:
            d = json.loads(f.read_text())
        except (json.JSONDecodeError, OSError):
            continue
        hit = locked_keyed(d)
        if hit and not key_satisfied(hit[1], tags, scripts):
            offenders.append((f.name[:-len(".utp.json")], hit[0], hit[1]))

    for f in UNPACKED.glob("*.git.json"):
        try:
            d = json.loads(f.read_text())
        except (json.JSONDecodeError, OSError):
            continue
        pl = gv(d.get("Placeable List")) or []
        stem = f.name[:-len(".git.json")]
        seen = set()
        for inst in pl:
            hit = locked_keyed(inst)
            if hit and not key_satisfied(hit[1], tags, scripts):
                if hit in seen:      # collapse duplicate instances of same chest tag
                    continue
                seen.add(hit)
                offenders.append((stem, hit[0], hit[1]))

    new = [o for o in offenders if (o[0], o[1]) not in KNOWN]
    known = [o for o in offenders if (o[0], o[1]) in KNOWN]

    for stem, tag, key in known:
        print(f"check_container_keys: KNOWN (reported, not gated) — "
              f"{stem}:{tag} needs key '{key}'")

    if new:
        print(f"check_container_keys: {len(new)} container(s) locked with a key "
              f"that has no source:")
        for stem, tag, key in new:
            print(f"  - {stem}:{tag} — KeyName '{key}' has no .uti blueprint and "
                  f"no script mints it")
        print("  remedy: create the key item (Tag = KeyName), or have a script "
              "mint it, or clear the phantom KeyName / lower the lock.")
        return 1

    print(f"check_container_keys: OK — every locked+keyed container has an "
          f"obtainable key ({len(known)} known-unfixed reported).")
    return 0


if __name__ == "__main__":
    sys.exit(main())

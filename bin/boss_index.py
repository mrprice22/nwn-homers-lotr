#!/usr/bin/env python3
"""Shared module-scan helpers for the Roll of the Fallen boss registry.

Both the build gate (tests/check_boss_registry.py) and the registry generator
(bin/gen-boss-registry.py) need the same view of the module: where every
creature is placed, which encounter slots reference it, and the resolved
blueprint fields. Keeping that logic here means the "single-instance"
determination has exactly one implementation.
"""
import functools
import json
import unicodedata
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
UNPACKED = ROOT / "unpacked"


def gv(node):
    """Unwrap a GFF-as-JSON typed node ({"type":..,"value":..}) to its value."""
    return node["value"] if isinstance(node, dict) and "value" in node else node


def locstr(node):
    """Resolve a cexolocstring node to its English (lang 0) string."""
    v = gv(node)
    if isinstance(v, dict):
        v = v.get("0") or (next(iter(v.values())) if v else "")
    return v if isinstance(v, str) else ""


def ascii_fold(s):
    """Fold a display name to ASCII — non-ASCII bytes in NWScript string
    literals are a known compiler hazard (Khamûl->Khamul, Númenor->Numenor)."""
    for a, b in (("’", "'"), ("‘", "'"), ("“", '"'),
                 ("”", '"'), ("–", "-"), ("—", "-")):
        s = s.replace(a, b)
    s = unicodedata.normalize("NFKD", s)
    s = s.encode("ascii", "ignore").decode("ascii")
    return " ".join(s.split())


def build_placement_indices(unpacked=UNPACKED):
    """Scan every *.git.json once.

    Returns (placements, enc_slots):
      placements: TemplateResRef -> [(area_resref, instance_tag_override or None,
                                     instance_ScriptDeath_override or None)]
      enc_slots:  creature ResRef -> [(area_resref, enc_template, enc_struct)]
    """
    placements = {}
    enc_slots = {}
    for git in sorted(unpacked.glob("*.git.json")):
        area = git.name.replace(".git.json", "")
        data = json.loads(git.read_text())
        for c in gv(data.get("Creature List")) or []:
            placements.setdefault(gv(c.get("TemplateResRef")), []).append(
                (area, gv(c.get("Tag")), (gv(c.get("ScriptDeath")) or "").lower()))
        for e in gv(data.get("Encounter List")) or []:
            for slot in gv(e.get("CreatureList")) or []:
                enc_slots.setdefault(gv(slot.get("ResRef")), []).append(
                    (area, gv(e.get("TemplateResRef")), e))
    return placements, enc_slots


@functools.lru_cache(maxsize=None)
def _area_names(unpacked_str):
    names = {}
    for are in Path(unpacked_str).glob("*.are.json"):
        rr = are.name.replace(".are.json", "")
        names[rr] = locstr(json.loads(are.read_text()).get("Name")) or rr
    return names


def area_name(area_resref, unpacked=UNPACKED):
    return _area_names(str(unpacked)).get(area_resref, area_resref)


@functools.lru_cache(maxsize=None)
def faction_names(unpacked_str):
    d = json.loads((Path(unpacked_str) / "repute.fac.json").read_text())
    return {i: locstr(f.get("FactionName"))
            for i, f in enumerate(gv(d.get("FactionList")) or [])}


def load_blueprint(resref, unpacked=UNPACKED):
    """Resolved creature-blueprint fields, or None if the .utc.json is absent."""
    p = unpacked / f"{resref}.utc.json"
    if not p.exists():
        return None
    d = json.loads(p.read_text())
    name = (locstr(d.get("FirstName")) + " " + locstr(d.get("LastName"))).strip()
    fid = gv(d.get("FactionID"))
    return {
        "resref": resref,
        "name": name or resref,
        "tag": gv(d.get("Tag")) or "",
        "cr": float(gv(d.get("ChallengeRating")) or 0),
        "faction_id": fid,
        "faction_name": faction_names(str(unpacked)).get(fid, str(fid)),
        "plot": int(gv(d.get("Plot")) or 0),
        "immortal": int(gv(d.get("IsImmortal")) or 0),
        "race": gv(d.get("Race")),
        "hp": gv(d.get("MaxHitPoints")) or gv(d.get("HitPoints")) or 0,
        "script_death": (gv(d.get("ScriptDeath")) or "").lower(),
        "appearance": gv(d.get("Appearance_Type")),
    }

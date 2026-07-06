#!/usr/bin/env python3
"""Resolve duplicate-tagged items so every distinct item has a unique Tag.

Scripts, the engine, stores, journals and the Forge contraband whitelist all
look items up by Tag. When two items that differ in properties share a Tag, the
lookup is ambiguous and the Forge whitelist (one fingerprint per tag/resref)
cannot represent both. This tool audits the module and gives each conflicting
variant its own Tag (and, for inline overrides, its own blueprint + resref).

It scans unpacked/ DIRECTLY and recomputes conflicts itself. module-index/
item_tag_conflicts.json (refreshed only by the wiki build, which must not run in
this pipeline) is consulted ONLY as an optional supplement, to catch conflicts
whose other side is a BASE-GAME item that never appears in unpacked/.

Per conflict group, members are grouped by property signature. One signature
(the canonical blueprint's) keeps the shared Tag; every other signature gets a
fresh unique Tag. Each member is then fixed by the cheapest safe rewrite:

  A  blueprint retag   — a real .uti blueprint that isn't canonical: rewrite its
                         Tag (and the Tag of its non-deviating placements).
  B  promote           — an inline override (full struct deviating from its
                         TemplateResRef blueprint) with no same-sig blueprint:
                         write a new .uti with a unique resref+Tag and re-point
                         every embedded occurrence at it.
  R  repoint           — an override whose signature matches an existing
                         blueprint: re-point occurrences to that blueprint.
  T  retag-in-place    — an override EQUIPPED on a creature: changing its resref
                         would make the placement diverge from its blueprint on
                         respawn (check_divergent_creatures), so only its Tag is
                         rewritten (resref preserved).
  G  base-game retag   — a module .uti that borrowed a base-game item's resref
                         as its Tag; the base-game side is uneditable, so the
                         module blueprint is retagged. (Uses the wiki report to
                         see the base-game side, which the source scan cannot.)

DEFERRED: a tag used as a literal argument to a tag-lookup builtin in a
hand-written script (GetItemPossessedBy, HasItem, …) is a quest/script key;
renaming its item would break the script, so those groups are left intact and
listed for manual review.

LEGACY FORGE SAFETY: B/R change an item's resref, so copies players already
carry hash under the OLD resref. bin/gen-forge-legal.py reads the map below and
re-whitelists those legacy fingerprints, so no one is jailed after deploy — no
player .bic edit is required for forge safety.

Usage:
    python3 bin/dedupe-item-tags.py            # dry-run report (default)
    python3 bin/dedupe-item-tags.py --apply    # write source edits + map CSV

dedupe-item-tags-map.csv (committed) records every rename for reproducibility
and for the forge legacy-whitelist. Re-run gen-forge-legal.py after --apply.
"""

import argparse
import csv
import json
import re
import sys
from collections import defaultdict
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
UNPACKED = REPO / "unpacked"
MAP_CSV = REPO / "dedupe-item-tags-map.csv"
REPORT = REPO / "module-index" / "item_tag_conflicts.json"

INSTANCE_GLOBS = ("*.git.json", "*.utc.json", "*.utm.json", "*.utp.json")
LITERAL_GLOBS = ("*.nss", "*.utm.json", "module.jrl.json")
RESREF_MAX = 16  # NWN resref length limit


def gval(struct, field, default=None):
    f = struct.get(field)
    return f["value"] if isinstance(f, dict) and "value" in f else default


def set_field(struct, field, ftype, value):
    struct[field] = {"type": ftype, "value": value}


def prop_sig(struct):
    """Frozenset fingerprint of an item's permanent property tuples."""
    out = []
    for p in (gval(struct, "PropertiesList") or []):
        out.append((
            gval(p, "PropertyName", 0), gval(p, "Subtype", 0),
            gval(p, "CostTable", 0), gval(p, "CostValue", 0),
            gval(p, "Param1", 255), gval(p, "Param1Value", 0),
        ))
    return frozenset(out)


def item_name(struct, resref):
    loc = struct.get("LocalizedName")
    if isinstance(loc, dict):
        v = loc.get("value")
        if isinstance(v, dict) and v:
            langs = sorted((k for k in v if str(k).isdigit()), key=int)
            if langs:
                return v[langs[0]]
    return resref


def eff_tag(struct, resref):
    t = (gval(struct, "Tag") or "").strip()
    return t if t else resref


def walk_item_structs(node, equipped=False):
    """Yield (item struct, equipped?) for every embedded full item struct.

    'equipped' is True when the struct sits under a creature's Equip_ItemList —
    the only carried-item list the respawn-divergence gate compares by resref,
    so equipped overrides must be retagged in place rather than re-pointed.
    """
    if isinstance(node, dict):
        if "TemplateResRef" in node and "PropertiesList" in node:
            yield node, equipped
        for k, v in node.items():
            yield from walk_item_structs(v, equipped or k == "Equip_ItemList")
    elif isinstance(node, list):
        for v in node:
            yield from walk_item_structs(v, equipped)


class Model:
    def __init__(self):
        self.blueprints = {}     # resref -> {tag, sig, name, cost, path}
        self.instances = []      # {file, struct, resref, tag, sig, name}
        self.docs = {}           # Path -> parsed json (for write-back)
        self._load()

    def _doc(self, path):
        if path not in self.docs:
            self.docs[path] = json.loads(path.read_text())
        return self.docs[path]

    def _load(self):
        for f in sorted(UNPACKED.glob("*.uti.json")):
            d = self._doc(f)
            resref = f.name[: -len(".uti.json")].lower()
            self.blueprints[resref] = {
                "tag": eff_tag(d, resref), "sig": prop_sig(d),
                "name": item_name(d, resref),
                "cost": int(gval(d, "Cost", 0) or 0), "path": f,
            }
        for glob in INSTANCE_GLOBS:
            for f in sorted(UNPACKED.glob(glob)):
                for st, equipped in walk_item_structs(self._doc(f)):
                    resref = (gval(st, "TemplateResRef") or "").lower()
                    if not resref:
                        continue
                    self.instances.append({
                        "file": f, "struct": st, "resref": resref,
                        "tag": eff_tag(st, resref), "sig": prop_sig(st),
                        "name": item_name(st, resref), "equipped": equipped,
                    })

    # ---- variant universe -------------------------------------------------

    def build_variant_universe(self):
        """blueprints + deviating overrides (deduped by base resref + sig).

        Empty-PropertiesList embeds are treated as plain blueprint references
        (the wiki does the same) — never as deviating overrides.
        """
        variants = []
        for rr, bp in self.blueprints.items():
            variants.append({
                "key": rr, "resref": rr, "tag": bp["tag"], "sig": bp["sig"],
                "kind": "blueprint", "name": bp["name"], "cost": bp["cost"],
                "base": rr, "occurrences": [],
            })
        overrides = {}
        vn = defaultdict(int)
        for inst in self.instances:
            if len(inst["sig"]) == 0:
                continue  # empty props -> plain reference, not an override
            base = inst["resref"]
            bp = self.blueprints.get(base)
            if bp is not None and inst["sig"] == bp["sig"]:
                continue  # matches blueprint
            k = (base, inst["sig"])
            v = overrides.get(k)
            if v is None:
                vn[base] += 1
                start = 2 if base in self.blueprints else 1
                synth = f"{base}__v{vn[base] + start - 1}"
                v = overrides[k] = {
                    "key": synth, "resref": synth, "tag": inst["tag"],
                    "sig": inst["sig"], "kind": "override", "name": inst["name"],
                    "cost": int(gval(inst["struct"], "Cost", 0) or 0),
                    "base": base, "occurrences": [], "equipped": False,
                }
                variants.append(v)
            v["occurrences"].append(inst)
            if inst["equipped"]:
                v["equipped"] = True
        return variants

    def conflicts_from(self, universe):
        groups = defaultdict(list)
        for v in universe:
            groups[v["tag"].strip().lower()].append(v)
        out = []
        for tag_lc, vs in sorted(groups.items()):
            if len(vs) >= 2 and len({v["sig"] for v in vs}) >= 2:
                out.append((tag_lc, vs))
        return out

    def conflicts(self):
        """List of (tag_lc, [variants]) sharing a tag with >1 distinct sig."""
        return self.conflicts_from(self.build_variant_universe())

    def basegame_tags(self):
        """Lowercased tags that an uneditable base-game item holds (from the
        report). A module item can never keep such a tag without colliding."""
        if not REPORT.exists():
            return frozenset()
        rep = json.loads(REPORT.read_text())
        out = set()
        for c in rep["conflicts"]:
            for v in c["variants"]:
                rr = v["resref"]
                if "__v" not in rr and not (UNPACKED / f"{rr}.uti.json").exists():
                    out.add(c["shared_tag"].strip().lower())
                    break
        return frozenset(out)

    def basegame_actions(self, universe):
        """From the wiki report, conflicts my source scan can't see because the
        other side is a BASE-GAME item absent from unpacked/. Returns a list of
        {shared_tag, mode: 'uti'|'embed', variant} for the MODULE-editable side.
        """
        if not REPORT.exists():
            return []
        rep = json.loads(REPORT.read_text())
        my_tags = {t for t, _ in self.conflicts_from(universe)}
        ov_by_base_tag = defaultdict(list)
        for v in universe:
            if v["kind"] == "override":
                ov_by_base_tag[(v["base"], v["tag"].strip().lower())].append(v)
        # A report variant is "external" (base-game, uneditable) when it is NOT
        # a wiki-synthesised override (no "__v") and has no .uti file on disk.
        # A conflict with no external side lives entirely in unpacked/, so the
        # source scan owns it — skip it here (keeps this idempotent post-apply).
        def is_external(rr):
            return "__v" not in rr and not (UNPACKED / f"{rr}.uti.json").exists()
        out = []
        for c in rep["conflicts"]:
            tag_lc = c["shared_tag"].strip().lower()
            if tag_lc in my_tags:
                continue  # already handled from source
            if not any(is_external(v["resref"]) for v in c["variants"]):
                continue  # no base-game side — source scan's responsibility
            for var in c["variants"]:
                rr = var["resref"]
                if rr in self.blueprints:
                    # idempotent: only if the .uti STILL carries the shared tag
                    if self.blueprints[rr]["tag"].strip().lower() != tag_lc:
                        continue
                    out.append({"shared_tag": c["shared_tag"], "mode": "uti",
                                "resref": rr})
                else:
                    for ov in ov_by_base_tag.get((rr, tag_lc), []):
                        out.append({"shared_tag": c["shared_tag"],
                                    "mode": "embed", "variant": ov})
        return out


# ---- name derivation ------------------------------------------------------

class NameAllocator:
    def __init__(self, model):
        self.tags = set()
        self.resrefs = set(model.blueprints)
        for bp in model.blueprints.values():
            self.tags.add(bp["tag"].lower())
            self.resrefs.add(bp["path"].name[: -len(".uti.json")].lower())
        for i in model.instances:
            self.tags.add(i["tag"].lower())
            self.resrefs.add(i["resref"])

    def tag(self, base):
        n = 2
        while f"{base}{n}".lower() in self.tags:
            n += 1
        t = f"{base}{n}"
        self.tags.add(t.lower())
        return t

    def resref(self, base):
        n = 2
        while True:
            suffix = str(n)
            stem = base[: RESREF_MAX - len(suffix)]
            cand = f"{stem}{suffix}"
            if cand.lower() not in self.resrefs:
                self.resrefs.add(cand.lower())
                return cand
            n += 1


# ---- planning -------------------------------------------------------------

def plan_group(variants, alloc, basegame_tags=frozenset()):
    """Resolve one conflict group. Members are grouped by property signature;
    one signature (the canonical blueprint's) keeps the shared tag, every other
    signature gets a fresh unique tag. Blueprints are retagged in place;
    override instances re-point to a same-signature blueprint if one exists,
    otherwise the first such override is promoted to a new blueprint the rest
    re-point to. Handles pure-A, pure-B and MIXED groups uniformly.

    If the shared tag is ALSO held by an uneditable base-game item
    (orig_tag in basegame_tags), even the canonical signature is retagged, so
    the whole module side vacates the colliding tag.
    """
    by_sig = defaultdict(list)
    for v in variants:
        by_sig[v["sig"]].append(v)
    bps = [v for v in variants if v["kind"] == "blueprint"]
    key = lambda v: (v["tag"].lower() == v["resref"].lower(), v["cost"], v["resref"])
    canon = max(bps, key=key) if bps else max(variants, key=lambda v: (v["cost"], v["resref"]))
    orig_tag, canon_sig = canon["tag"], canon["sig"]
    keep_orig = orig_tag.strip().lower() not in basegame_tags

    sig_tag = {sig: (orig_tag if (sig == canon_sig and keep_orig) else alloc.tag(orig_tag))
               for sig in by_sig}
    # representative real blueprint per signature (for re-pointing overrides)
    sig_repref = {}
    for sig, members in by_sig.items():
        bp = next((v for v in members if v["kind"] == "blueprint"), None)
        sig_repref[sig] = bp["resref"] if bp else None

    acts = []
    for sig, members in by_sig.items():
        tag = sig_tag[sig]
        for v in members:
            if v["kind"] == "blueprint":
                if v["tag"] != tag:
                    acts.append({"cls": "A", "variant": v, "old_tag": v["tag"],
                                 "old_resref": v["resref"], "new_tag": tag,
                                 "new_resref": v["resref"]})
            elif v.get("equipped"):
                # Equipped on a creature: changing the resref would make the
                # placement's equipment diverge from its blueprint (respawn
                # gate). Retag the inline struct in place instead — keeps the
                # resref, still gives the item a unique tag.
                acts.append({"cls": "T", "variant": v, "old_tag": v["tag"],
                             "old_resref": v["base"], "new_tag": tag,
                             "new_resref": v["base"]})
            else:  # override
                rep = sig_repref[sig]
                if rep is not None:
                    acts.append({"cls": "R", "variant": v, "old_tag": v["tag"],
                                 "old_resref": v["base"], "new_tag": tag,
                                 "new_resref": rep})
                else:
                    rep = alloc.resref(v["base"])
                    sig_repref[sig] = rep  # later overrides of this sig reuse it
                    acts.append({"cls": "B", "variant": v, "old_tag": v["tag"],
                                 "old_resref": v["base"], "new_tag": tag,
                                 "new_resref": rep})
    return acts


def plan(model):
    """Return (actions, deferred). `deferred` is the list of (tag_lc, reason)
    conflict groups left unresolved because renaming would break a script."""
    alloc = NameAllocator(model)
    universe = model.build_variant_universe()
    basegame_tags = model.basegame_tags()
    protected = protected_tags()
    actions, deferred = [], []
    for tag_lc, variants in model.conflicts_from(universe):
        if tag_lc in protected:
            deferred.append((tag_lc, "tag is a script lookup key"))
            continue
        actions += plan_group(variants, alloc, basegame_tags)
    # base-game collisions (report-supplemented): retag/​promote the module side
    for ba in model.basegame_actions(universe):
        if ba["shared_tag"].strip().lower() in protected:
            deferred.append((ba["shared_tag"].strip().lower(), "tag is a script lookup key"))
            continue
        if ba["mode"] == "uti":
            rr = ba["resref"]
            v = {"kind": "blueprint", "resref": rr, "tag": ba["shared_tag"],
                 "base": rr, "occurrences": [], "name": model.blueprints[rr]["name"]}
            actions.append({
                "cls": "G", "old_tag": ba["shared_tag"], "old_resref": rr,
                "new_tag": alloc.tag(ba["shared_tag"]), "new_resref": rr, "variant": v,
            })
        else:  # embed -> promote
            v = ba["variant"]
            actions.append({
                "cls": "B", "old_tag": v["tag"], "old_resref": v["base"],
                "new_tag": alloc.tag(v["tag"]),
                "new_resref": alloc.resref(v["base"]), "variant": v,
            })
    return actions, deferred


# ---- literal-reference safety scan ---------------------------------------

# Bioware builtins + module wrappers that resolve an object by TAG. A tag passed
# to one of these from a hand-written script is a lookup key: renaming the item
# that carries it would break the script, so such tags are protected from
# renaming (the conflict is reported as deferred instead).
TAG_LOOKUP_FUNCS = (
    "GetItemPossessedBy", "GetObjectByTag", "GetNearestObjectByTag",
    "GetItemPossessedByTag", "GetWaypointByTag",
    "HasItem", "CheckPlayerForItem",
)
_GENERATED_NSS = {"forge_legal_inc.nss"}  # regenerated; not authoritative


def protected_tags():
    """Lowercased tags used as a literal argument to a tag-lookup function in a
    hand-written .nss. These must not be renamed. The pattern spans nested
    parens (e.g. HasItem(GetPCSpeaker(), "Tag")) but stops at the statement ';'.
    """
    funcs = "|".join(re.escape(f) for f in TAG_LOOKUP_FUNCS)
    pat = re.compile(r'(?:%s)\s*\([^;]{0,200}?"([^"]+)"' % funcs)
    out = set()
    for f in sorted(UNPACKED.glob("*.nss")):
        if f.name in _GENERATED_NSS:
            continue
        try:
            s = f.read_text(encoding="latin-1")
        except OSError:
            continue
        for m in pat.finditer(s):
            out.add(m.group(1).strip().lower())
    return out


def scan_literals(old_tags):
    """Map old_tag -> [files] where it appears as a literal in scripts/stores/journal."""
    hits = defaultdict(set)
    lowered = {t.lower(): t for t in old_tags}
    files = []
    for g in LITERAL_GLOBS:
        files += sorted(UNPACKED.glob(g))
    for f in files:
        try:
            s = f.read_text(encoding="latin-1")
        except OSError:
            continue
        for t in old_tags:
            if t and t in s:
                hits[t].add(f.name)
    return {t: sorted(v) for t, v in hits.items()}


# ---- apply ----------------------------------------------------------------

STRIP_ON_PROMOTE = {
    "XPosition", "YPosition", "ZPosition", "XOrientation", "YOrientation",
    "Dropable", "__struct_id", "Repos_PosX", "Repos_PosY", "Repos_Index",
}


def promote_blueprint(model, action):
    """Write a new .uti.json for a Class B override from a representative struct."""
    v = action["variant"]
    src = v["occurrences"][0]["struct"]
    new = {k: val for k, val in src.items() if k not in STRIP_ON_PROMOTE}
    set_field(new, "TemplateResRef", "resref", action["new_resref"])
    set_field(new, "Tag", "cexostring", action["new_tag"])
    # GFF root envelope: a standalone blueprint needs __data_type and no root
    # __struct_id (unlike the embedded struct it was copied from).
    new.pop("__struct_id", None)
    new = {"__data_type": "UTI ", **new}
    path = UNPACKED / f"{action['new_resref']}.uti.json"
    path.write_text(json.dumps(new, indent=2, ensure_ascii=False) + "\n")
    return path


def apply_plan(model, actions):
    """Apply a (possibly class-filtered) list of rename actions."""
    changed_docs = set()
    written_uti = []
    handled_structs = {id(occ["struct"]) for a in actions if a["cls"] in ("B", "R", "T")
                       for occ in a["variant"]["occurrences"]}
    # 1. retag blueprint .uti files (Class A + base-game)
    for a in actions:
        if a["cls"] in ("A", "G"):
            path = model.blueprints[a["old_resref"]]["path"]
            set_field(model._doc(path), "Tag", "cexostring", a["new_tag"])
            changed_docs.add(path)
    # 2. Class B: promote override -> new .uti.  Class R: re-point to an existing
    #    same-signature blueprint.  Both re-point every embedded occurrence.
    #    Class T: equipped override — retag the inline struct only (keep resref).
    for a in actions:
        if a["cls"] in ("B", "R", "T"):
            if a["cls"] == "B":
                written_uti.append(promote_blueprint(model, a))
            for occ in a["variant"]["occurrences"]:
                if a["cls"] != "T":
                    set_field(occ["struct"], "TemplateResRef", "resref", a["new_resref"])
                set_field(occ["struct"], "Tag", "cexostring", a["new_tag"])
                changed_docs.add(occ["file"])
    # 3. follow each RENAMED blueprint's tag onto its own placed instances that
    #    still carry the OLD shared tag and match the blueprint (non-deviating).
    for a in actions:
        if a["cls"] not in ("A", "G"):
            continue
        rr, old, new = a["old_resref"], a["old_tag"], a["new_tag"]
        bp = model.blueprints.get(rr)
        for inst in model.instances:
            if inst["resref"] != rr or id(inst["struct"]) in handled_structs:
                continue
            if eff_tag(inst["struct"], rr).lower() != old.lower():
                continue  # instance already carries a different tag — leave it
            if bp is not None and len(inst["sig"]) > 0 and inst["sig"] != bp["sig"]:
                continue  # deviating override — handled elsewhere
            set_field(inst["struct"], "Tag", "cexostring", new)
            changed_docs.add(inst["file"])
    for path in sorted(changed_docs):
        path.write_text(json.dumps(model._doc(path), indent=2, ensure_ascii=False) + "\n")
    return changed_docs, written_uti


def write_map(actions):
    with MAP_CSV.open("w", newline="") as fh:
        w = csv.writer(fh)
        w.writerow(["class", "name", "old_tag", "old_resref", "new_tag", "new_resref"])
        for a in sorted(actions, key=lambda a: (a["cls"], a["old_tag"].lower(), a["new_resref"])):
            w.writerow([a["cls"], a["variant"]["name"], a["old_tag"],
                        a["old_resref"], a["new_tag"], a["new_resref"]])


# ---- reporting ------------------------------------------------------------

def report(model, actions, deferred):
    universe = model.build_variant_universe()
    conflicts = model.conflicts_from(universe)
    bg = model.basegame_actions(universe)
    ca = sum(1 for _t, vs in conflicts if not any(v["kind"] == "override" for v in vs))
    cb = len(conflicts) - ca
    print(f"conflicts (source scan): {len(conflicts)}  "
          f"[Class A: {ca}, Class B: {cb}]  + base-game (report): {len(bg)}")
    print(f"blueprints: {len(model.blueprints)}  instance structs: {len(model.instances)}")
    by = defaultdict(int)
    for a in actions:
        by[a["cls"]] += 1
    print(f"planned renames: {len(actions)}  [A blueprint-retag: {by['A']}, "
          f"B promote-to-new-blueprint: {by['B']}, R repoint-to-existing: {by['R']}, "
          f"T equipped-retag-in-place: {by['T']}, base-game retag: {by['G']}]")
    if deferred:
        print(f"\n>> {len(deferred)} conflict(s) DEFERRED (tag is a script lookup key — "
              f"renaming would break a quest/script; left intact for manual review):")
        for tag_lc, reason in sorted(set(deferred)):
            print(f"   {tag_lc}")
    lit = scan_literals({a["old_tag"] for a in actions})
    if lit:
        print(f"\n!! {len(lit)} renamed tag(s) still appear as NON-lookup literals "
              f"(resref creates, dialog resrefs, generated files) — usually safe since "
              f"the canonical keeps the tag, but confirm:")
        for t in sorted(lit):
            print(f"   {t}: {', '.join(lit[t])}")


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--apply", action="store_true", help="write source edits + map CSV")
    args = ap.parse_args()

    model = Model()
    actions, deferred = plan(model)
    report(model, actions, deferred)

    if args.apply:
        changed, new_uti = apply_plan(model, actions)
        if actions:
            write_map(actions)  # full plan; never clobber the map with an empty
            print(f"\nwrote {MAP_CSV.relative_to(REPO)} ({len(actions)} rows)")
        else:
            print(f"\nnothing to apply — {MAP_CSV.name} left unchanged")
        print(f"applied: {len(changed)} files edited, {len(new_uti)} new .uti blueprints")
    else:
        print("(dry run — no source files written; --apply to write the map + edits)")


if __name__ == "__main__":
    main()

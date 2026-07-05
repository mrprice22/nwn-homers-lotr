#!/usr/bin/env python3
"""Generate the Roll of the Fallen boss registry from the module.

A "boss" is a creature blueprint that:
  * has ChallengeRating > 60, and
  * can only ever have ONE live instance in the world — exactly one placement
    and no encounter slot ("placed"), OR no placement and exactly one
    Max=1 / Respawns=-1 / Reset=1 encounter instance ("encounter"), and
  * is NOT plot or immortal (an unkillable NPC can't sit on a kill tracker), and
  * is NOT a merchant / utility NPC (see EXCLUDE + the merchant-faction filter).

This rewrites the BRD_SeedBoss / BRD_SeedAlias block between the
  // BEGIN GENERATED REGISTRY  ...  // END GENERATED REGISTRY
markers in unpacked/brd_db.nss. All three consumers of that block (the game, the
build gate tests/check_boss_registry.py, and the wiki's load_boss_registry) parse
the same text, so regenerating keeps the in-game board and the wiki in sync.

Default is a dry-run report; pass --write to rewrite brd_db.nss.
"""
import argparse
import functools
import re
import sys

import boss_index as bi
from boss_index import UNPACKED, gv, ascii_fold, area_name

CR_MIN = 60.0          # strictly greater than this
CR_ARTIFACT = 12000.0  # drop absurd CR (data artifacts); real max ~9540

# Curated non-combat / utility NPCs to keep off the board even though they pass
# the mechanical rule. The generator's report flags candidates for review; add
# confirmed non-bosses here.
EXCLUDE = {
    "methonashforge",   # "The Forger" — store keeper, CR artifact
    "methonashmart",    # "The Well-Mart" — store keeper, CR artifact
}

# Curated bosses to force onto the board even though they fall below CR_MIN
# (the rule's escape hatch — keep this small; it's the only manual curation).
INCLUDE = set()

# Soft signals (reported, not auto-excluded) that a candidate may be a vendor.
MERCHANTISH = re.compile(
    r"\b(mart|forger|smith|smithy|armou?rer|craftsman|merchant|shopkeep|vendor|"
    r"trader|banker|innkeep)", re.I)

RESPAWN_CALL = re.compile(r"\bSE_DoCreatureRespawn\s*\(")
EXEC_SCRIPT = re.compile(r'ExecuteScript\s*\(\s*"([^"]+)"')
CREATE_CRE = re.compile(r"CreateObject\s*\(\s*OBJECT_TYPE_CREATURE")
STATIC_SPAWN = re.compile(r"\bStaticSpawn\s*\(")
_COMMENT = re.compile(r"//[^\n]*|/\*.*?\*/", re.S)


def _death_respawn_kind(resref, _seen=()):
    """How OnDeath script <resref> brings the boss back:
      'standard' — calls SE_DoCreatureRespawn (exact 900s, matches the board);
      'legacy'   — re-creates a creature via StaticSpawn / CreateObject (comes
                   back, but on a non-standard timer the board can't predict);
      'none'     — no respawn; the boss stays dead until a server restart.
    Follows ExecuteScript chains."""
    if not resref or resref in _seen:
        return "none"
    p = UNPACKED / f"{resref}.nss"
    if not p.exists():
        return "none"
    src = _COMMENT.sub("", p.read_text(errors="replace"))
    if RESPAWN_CALL.search(src):
        return "standard"
    kind = "legacy" if (CREATE_CRE.search(src) or STATIC_SPAWN.search(src)) else "none"
    seen = _seen + (resref,)
    for m in EXEC_SCRIPT.finditer(src):
        k = _death_respawn_kind(m.group(1).lower(), seen)
        if k == "standard":
            return "standard"
        if k == "legacy":
            kind = "legacy"
    return kind


def stem(resref):
    return re.sub(r"\d+$", "", resref)


def classify(placements, enc_slots):
    """Yield (bp, kind, area, tag, respawn, enc_struct|None) for every CR>60
    single-instance candidate; collect exclusions separately."""
    included, excluded = [], []
    for utc in sorted(UNPACKED.glob("*.utc.json")):
        rr = utc.name.replace(".utc.json", "")
        bp = bi.load_blueprint(rr)
        if not bp or (bp["cr"] <= CR_MIN and rr not in INCLUDE):
            continue

        placed = placements.get(rr, [])
        slots = enc_slots.get(rr, [])
        total = len(placed) + len(slots)
        reason = None

        if bp["cr"] >= CR_ARTIFACT:
            reason = f"CR artifact ({bp['cr']:.0f})"
        elif rr in EXCLUDE:
            reason = "EXCLUDE denylist (merchant/utility)"
        elif bp["plot"]:
            reason = "plot NPC (unkillable)"
        elif bp["immortal"]:
            reason = "immortal NPC (unkillable)"
        elif bp["faction_name"] == "Merchant":
            reason = "Merchant faction"
        elif total == 0:
            reason = "never placed/spawned (unspawned or ds_* mirror)"
        elif total > 1:
            reason = (f"multi-instance: {len(placed)} placed + {len(slots)} "
                      f"encounter slots")
        elif placed and slots:
            reason = "both placed and in an encounter"

        if reason:
            excluded.append((bp, reason))
            continue

        if placed:  # exactly one placement, no encounter slot
            p_area, p_tag = placed[0]
            eff_tag = p_tag or bp["tag"]
            if "NSP" in (eff_tag or ""):
                excluded.append((bp, "tag contains NSP (se_respawn skips it)"))
                continue
            included.append((bp, "placed", p_area, eff_tag, 900, None))
        else:  # exactly one encounter slot
            e_area, _e_tmpl, e = slots[0]
            if gv(e.get("MaxCreatures")) != 1:
                excluded.append((bp, f"encounter MaxCreatures="
                                 f"{gv(e.get('MaxCreatures'))} (>1 can be alive)"))
                continue
            if gv(e.get("Respawns")) != -1 or gv(e.get("Reset")) != 1:
                excluded.append((bp, "encounter not infinitely re-arming"))
                continue
            included.append((bp, "encounter", e_area, bp["tag"],
                             gv(e.get("ResetTime")), e))
    return included, excluded


def group_aliases(included):
    """Collapse variant blueprints sharing one encounter instance + resref stem
    into one canonical row + alias rows. Returns (rows, aliases, alias_report)."""
    enc = [x for x in included if x[1] == "encounter"]
    other = [x for x in included if x[1] != "encounter"]

    groups = {}
    for x in enc:
        bp, _kind, _area, _tag, _resp, e = x
        groups.setdefault((id(e), stem(bp["resref"])), []).append(x)

    rows, aliases, report = [], [], []
    for members in groups.values():
        if len(members) == 1:
            rows.append(members[0])
            continue
        # canonical = the exact-stem member if present, else shortest resref
        st = stem(members[0][0]["resref"])
        members.sort(key=lambda m: (m[0]["resref"] != st, len(m[0]["resref"]),
                                    m[0]["resref"]))
        canon = members[0]
        cbp = canon[0]
        # represent the group's power by the strongest variant
        cr = max(m[0]["cr"] for m in members)
        cbp = dict(cbp, cr=cr)
        rows.append((cbp, canon[1], canon[2], canon[3], canon[4], canon[5]))
        for m in members[1:]:
            aliases.append((m[0]["resref"], cbp["resref"]))
        report.append((cbp["resref"], cr,
                       [m[0]["resref"] for m in members[1:]]))
    return rows + other, aliases, report


def drop_tag_area_collisions(rows):
    """Multiple blueprints sharing one tag AND one area means several copies are
    alive in the same place at once — not a 1-at-a-time boss. Drop the whole
    group. (Same tag in DIFFERENT areas is fine — the two Khamuls; those are
    kept because BRD_BossAlive keys on tag+area.)"""
    groups = {}
    for x in rows:
        _bp, _kind, area, tag, _resp, _e = x
        groups.setdefault((tag, area), []).append(x)
    kept, dropped = [], []
    for members in groups.values():
        (kept if len(members) == 1 else dropped).extend(members)
    return kept, dropped


def build_rows(rows):
    """Finalise display fields: ASCII names, dedup disambiguation, sort CR desc."""
    out = []
    for bp, kind, area, tag, respawn, _e in rows:
        out.append({
            "resref": bp["resref"],
            "name": ascii_fold(bp["name"]),
            "tag": tag,
            "area": area,
            "area_name": ascii_fold(area_name(area)),
            "cr": bp["cr"],
            "respawn": int(respawn or 900),
            "type": kind,
            "script_death": bp["script_death"],
            "faction": bp["faction_name"],
        })
    # disambiguate identical display names by area prefix (the two Khamuls)
    seen = {}
    for r in out:
        seen.setdefault(r["name"], []).append(r)
    for name, group in seen.items():
        if len(group) > 1:
            for r in group:
                r["name"] = f"{name} ({r['area_name'].split(':')[0].strip()})"
    out.sort(key=lambda r: (-r["cr"], r["name"]))
    return out


def render_block(rows, aliases):
    lines = ["    // BEGIN GENERATED REGISTRY — produced by bin/gen-boss-registry.py",
             "    // Do not hand-edit; run the generator to refresh (see "
             "CLAUDE-boss-tracker.md)."]
    for r in rows:
        lines.append(
            f'    BRD_SeedBoss({q(r["resref"])}, {q(r["name"])}, '
            f'{q(r["tag"])}, {q(r["area"])}, {q(r["area_name"])}, '
            f'{r["cr"]:.1f}, {r["respawn"]}, {q(r["type"])});')
    if aliases:
        lines.append("")
        lines.append("    // Variant blueprints that all represent one boss.")
        for a, canon in sorted(aliases):
            lines.append(f'    BRD_SeedAlias({q(a)}, {q(canon)});')
    lines.append("    // END GENERATED REGISTRY")
    return "\n".join(lines)


def q(s):
    return '"' + s.replace('"', '\\"') + '"'


def write_block(rows, aliases):
    path = UNPACKED / "brd_db.nss"
    src = path.read_text()
    begin = "    // BEGIN GENERATED REGISTRY"
    end = "    // END GENERATED REGISTRY"
    block = render_block(rows, aliases)
    if begin in src and end in src:
        pre = src[:src.index(begin)]
        post = src[src.index(end) + len(end):]
        src = pre + block + post
    else:
        # First run: replace the hand-written seed calls inside BRD_InitDb.
        # Anchor on the DELETE FROM boss_alias line, insert after it.
        anchor = 'SqlStep(q);\n'
        marker = 'DELETE FROM boss_alias'
        idx = src.index(marker)
        ins = src.index(anchor, idx) + len(anchor)
        # find the closing brace of BRD_InitDb after insertion point
        close = src.index("\n}", ins)
        src = src[:ins] + "\n" + block + "\n" + src[close:]
    path.write_text(src)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--write", action="store_true",
                    help="rewrite the block in unpacked/brd_db.nss")
    args = ap.parse_args()

    placements, enc_slots = bi.build_placement_indices()
    included, excluded = classify(placements, enc_slots)
    grouped, aliases, alias_report = group_aliases(included)
    grouped, collisions = drop_tag_area_collisions(grouped)
    for bp, _k, area, tag, _r, _e in collisions:
        excluded.append((bp, f"same tag+area copies (not 1-at-a-time): "
                         f"tag {tag} in {area}"))
    rows = build_rows(grouped)

    # Current registry, for a regression diff.
    cur_src = (UNPACKED / "brd_db.nss").read_text()
    cur = set(re.findall(r'BRD_SeedBoss\("([^"]+)"', cur_src))
    new = {r["resref"] for r in rows}

    print(f"=== INCLUDED: {len(rows)} bosses "
          f"({sum(r['type']=='placed' for r in rows)} placed, "
          f"{sum(r['type']=='encounter' for r in rows)} encounter), "
          f"{len(aliases)} aliases ===\n")
    none_respawn, legacy_respawn = [], []
    for r in rows:
        warn = ""
        if r["type"] == "placed":
            kind = _death_respawn_kind(r["script_death"])
            if kind == "none":
                warn = f"  !! no respawn (OnDeath '{r['script_death']}')"
                none_respawn.append(r)
            elif kind == "legacy":
                warn = f"  ~ legacy respawn ('{r['script_death']}')"
                legacy_respawn.append(r)
        print(f"  {r['cr']:7.0f}  {r['resref']:20s} {r['name'][:40]:40s} "
              f"{r['type']:9s} {r['area']:18s}{warn}")

    if alias_report:
        print("\n=== ALIAS GROUPS (variant blueprints -> canonical) ===")
        for canon, cr, variants in alias_report:
            print(f"  {canon} (CR {cr:.0f})  <- {', '.join(variants)}")

    if none_respawn:
        print(f"\n=== RESPAWN WARNINGS: {len(none_respawn)} placed boss(es) that "
              f"STAY DEAD until a server restart (OnDeath never respawns) ===")
        for r in none_respawn:
            print(f"  {r['resref']:20s} {r['name'][:34]:34s} OnDeath="
                  f"{r['script_death']}")
    if legacy_respawn:
        print(f"\n=== LEGACY RESPAWN: {len(legacy_respawn)} placed boss(es) that "
              f"respawn via the old spawn system (board 900s timer may not "
              f"match) ===")
        for r in legacy_respawn:
            print(f"  {r['resref']:20s} {r['name'][:34]:34s} OnDeath="
                  f"{r['script_death']}")

    # Unresolved identical display names (should be none after disambiguation).
    from collections import Counter
    dup = [n for n, c in Counter(r["name"] for r in rows).items() if c > 1]
    if dup:
        print(f"\n=== NAME COLLISIONS (identical labels): {dup} ===")

    merch_ish = [r for r in rows if MERCHANTISH.search(r["name"])]
    if merch_ish:
        print("\n=== MERCHANT-ISH NAMES among included (review; add to EXCLUDE "
              "if vendor) ===")
        for r in merch_ish:
            print(f"  {r['resref']:20s} {r['name'][:36]:36s} "
                  f"faction={r['faction']}")

    dropped = sorted(cur - new)
    added = sorted(new - cur)
    if dropped:
        print(f"\n=== DROPPED from current registry: {len(dropped)} ===")
        exmap = {bp["resref"]: why for bp, why in excluded}
        aliased = {a for a, _ in aliases}
        for rr in dropped:
            why = exmap.get(rr)
            if not why and rr in aliased:
                why = "now an alias of its canonical"
            if not why:
                bp = bi.load_blueprint(rr)
                why = (f"CR {bp['cr']:.0f} <= {CR_MIN:.0f} (below boss floor)"
                       if bp else "blueprint missing")
            print(f"  {rr:20s} {why}")
    print(f"\n=== ADDED vs current registry: {len(added)} new ===")

    names = ["rancid", "glorfindel", "aragorn", "gimli", "sarah", "gothmog"]
    print("\n=== NAMED-EXAMPLE CHECK ===")
    for n in names:
        hits = [r for r in rows if n in r["name"].lower()]
        exhits = [(bp, why) for bp, why in excluded if n in bp["name"].lower()]
        if hits:
            print(f"  {n:12s} INCLUDED: " +
                  ", ".join(f"{r['resref']}({r['name']})" for r in hits))
        elif exhits:
            print(f"  {n:12s} EXCLUDED: " +
                  ", ".join(f"{bp['resref']} [{why}]" for bp, why in exhits))
        else:
            print(f"  {n:12s} NOT FOUND among CR>60 candidates")

    print(f"\n=== EXCLUDED (CR>60 but filtered): {len(excluded)} ===")
    by_reason = {}
    for bp, why in excluded:
        by_reason.setdefault(why.split(":")[0].split("(")[0].strip(), 0)
        by_reason[why.split(":")[0].split("(")[0].strip()] += 1
    for why, n in sorted(by_reason.items(), key=lambda x: -x[1]):
        print(f"  {n:4d}  {why}")

    if args.write:
        write_block(rows, aliases)
        print(f"\nWrote {len(rows)} bosses + {len(aliases)} aliases to "
              f"unpacked/brd_db.nss")
    else:
        print("\n(dry run — pass --write to rewrite unpacked/brd_db.nss)")
    return 0


if __name__ == "__main__":
    sys.exit(main())

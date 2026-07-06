#!/usr/bin/env python3
"""Generate unpacked/forge_legal_inc.nss — the Forge legal-variant whitelist.

The Forge contraband system (forge_inc.nss) jails players whose items exceed
the legal caps AND deviate from their stock .uti blueprint. But the module
embeds many items as FULL structs (own PropertiesList) inside .git.json files
(embedded stores, creature inventories/equipment, placeable loot). Those are
legally obtainable yet deviate from the same-resref blueprint — without this
whitelist, players who buy/loot them get jailed (false positive).

This script scans every embedded item struct in unpacked/, fingerprints the
ones that deviate from (or have no) module .uti blueprint, and emits
ForgeIsKnownLegalVariant() consulted by ForgeIsItemIllegal().

Fingerprint: "<resref>|" + ",".join(sorted("ttttt:sssss:ccccc:ppppp")) over
permanent item properties, zero-padded to width 5 so lexicographic order ==
numeric order (the NWScript side insertion-sorts the same fixed-width strings).
Fields per property, normalized to what the runtime getters return:

  t = PropertyName                  (GetItemPropertyType)
  s = Subtype                       (GetItemPropertySubType; negative -> 65535)
  c = CostValue                     (GetItemPropertyCostTableValue; neg -> 65535)
  p = Param1Value, but 65535 when   (GetItemPropertyParam1Value; "no param1"
      Param1 == 255 ("no param1")    detected via GetItemPropertyParam1)

If in-game FORGE_DEBUG fp= logs ever disagree with generated entries, adjust
normalize_prop() here (runtime getters are ground truth) and regenerate.

Usage:
    python3 bin/gen-forge-legal.py [--dry-run] [--all]

  --dry-run  print the summary and would-be entries, write nothing
  --all      also include every no-blueprint fingerprint regardless of the
             cap-plausibility filter (bigger file; normally unnecessary)

If dedupe-item-tags-map.csv is present (bin/dedupe-item-tags.py), the whitelist
also re-includes each promoted/re-pointed item's PRE-dedup resref fingerprint,
so copies players already carry are not jailed after the rename lands.

Re-run after editing store inventories, creature loot, or placed container
items, or after re-running the tag dedup, then repack. Do not hand-edit
forge_legal_inc.nss.
"""

import json
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
UNPACKED = REPO / "unpacked"
OUTPUT = UNPACKED / "forge_legal_inc.nss"

# Mirror of forge_inc.nss caps; no-blueprint entries are only emitted when an
# item could plausibly trip them (with a 2x value margin, since the runtime
# GetGoldPieceValue can disagree with the embedded Cost field).
LEGAL_MAX_PROPS = 6
VALUE_THRESHOLD = 375000

CHUNK_SIZE = 100  # fingerprint compares per NWScript helper function


def gval(struct, field, default=None):
    f = struct.get(field)
    return f["value"] if isinstance(f, dict) and "value" in f else default


# Cosmetic property types excluded from all forge counting and fingerprinting:
# weapon visual effects (Bree appearance station) and Light of any color or
# brightness (Continual Flame, gems of power). Mirrors forge_inc.nss's
# ForgeIsCosmeticProp and the emitted ForgeLegalFingerprint.
COSMETIC_PROPS = {83, 44}  # ITEM_PROPERTY_VISUALEFFECT, ITEM_PROPERTY_LIGHT


def normalize_prop(p):
    t = gval(p, "PropertyName", 0)
    s = gval(p, "Subtype", 0)
    c = gval(p, "CostValue", 0)
    if gval(p, "Param1", 255) == 255:
        pv = 65535
    else:
        pv = gval(p, "Param1Value", 0)
    return "%05d:%05d:%05d:%05d" % (t, s, c, pv)


def fingerprint(resref, props):
    return resref.lower() + "|" + ",".join(sorted(
        normalize_prop(p) for p in props
        if gval(p, "PropertyName", 0) not in COSMETIC_PROPS))


def item_props(struct):
    return [p for p in (gval(struct, "PropertiesList") or [])]


def walk_items(node, out):
    """Collect every embedded full item struct (TemplateResRef + PropertiesList)."""
    if isinstance(node, dict):
        if "TemplateResRef" in node and "PropertiesList" in node:
            out.append(node)
        for v in node.values():
            walk_items(v, out)
    elif isinstance(node, list):
        for v in node:
            walk_items(v, out)


def legacy_fingerprints(blueprints):
    """Fingerprints for items players may still carry under a pre-dedup resref.

    Reads dedupe-item-tags-map.csv (bin/dedupe-item-tags.py). For each B/R row
    the item's resref changed from old_resref to new_resref; a player copy still
    hashes as fingerprint(old_resref, <new blueprint props>). Returns that set so
    those legitimate legacy items stay whitelisted. Empty if the map is absent.
    """
    import csv
    map_path = REPO / "dedupe-item-tags-map.csv"
    if not map_path.exists():
        return set()
    out = set()
    with map_path.open(newline="") as fh:
        for row in csv.DictReader(fh):
            if row["class"] not in ("B", "R"):
                continue
            uti = UNPACKED / f"{row['new_resref']}.uti.json"
            if not uti.exists():
                continue
            props = item_props(json.loads(uti.read_text()))
            out.add(fingerprint(row["old_resref"], props))
    return out


def main():
    dry_run = "--dry-run" in sys.argv
    include_all = "--all" in sys.argv

    blueprints = {}  # resref -> fingerprint
    for f in sorted(UNPACKED.glob("*.uti.json")):
        d = json.loads(f.read_text())
        resref = f.name[: -len(".uti.json")].lower()
        blueprints[resref] = fingerprint(resref, item_props(d))

    deviant = {}      # fingerprint -> example source file (has module blueprint)
    no_blueprint = {}  # fingerprint -> (source file, capworthy)
    scan = sorted(UNPACKED.glob("*.git.json")) + sorted(UNPACKED.glob("*.utc.json"))
    for f in scan:
        items = []
        walk_items(json.loads(f.read_text()), items)
        for it in items:
            resref = (gval(it, "TemplateResRef") or "").lower()
            if not resref:
                continue
            fp = fingerprint(resref, item_props(it))
            if resref in blueprints:
                if fp != blueprints[resref]:
                    deviant.setdefault(fp, f.name)
            else:
                nprops = len(item_props(it))
                value = (gval(it, "Cost", 0) * max(1, gval(it, "StackSize", 1))
                         + gval(it, "AddCost", 0))
                capworthy = nprops > LEGAL_MAX_PROPS or value > VALUE_THRESHOLD
                prev = no_blueprint.get(fp)
                no_blueprint[fp] = (f.name, capworthy or (prev[1] if prev else False))

    nb_kept = {fp: src for fp, (src, cap) in no_blueprint.items()
               if cap or include_all}

    # Legacy fingerprints from the item-tag dedup (bin/dedupe-item-tags.py).
    # Promoting/​re-pointing an override changed its resref, so copies players
    # already carry hash under the OLD resref and would otherwise fall off the
    # whitelist and be jailed. Re-add old_resref|props for every B/R migration
    # (T keeps its resref, so it is already covered by the source scan above).
    legacy = legacy_fingerprints(blueprints)

    entries = sorted(set(deviant) | set(nb_kept) | set(legacy))

    print("blueprints scanned:        %d" % len(blueprints))
    print("deviant variants (w/ uti): %d" % len(deviant))
    print("no-blueprint fingerprints: %d (kept after cap filter: %d)"
          % (len(no_blueprint), len(nb_kept)))
    print("legacy dedup fingerprints: %d" % len(legacy))
    print("total whitelist entries:   %d" % len(entries))

    if dry_run:
        for fp in entries:
            print(fp)
        print("(dry run — nothing written)")
        return

    chunks = [entries[i:i + CHUNK_SIZE] for i in range(0, len(entries), CHUNK_SIZE)]

    lines = []
    lines.append("// forge_legal_inc.nss — GENERATED by bin/gen-forge-legal.py. DO NOT HAND-EDIT.")
    lines.append("//")
    lines.append("// Whitelist of %d legally-obtainable item variants whose properties" % len(entries))
    lines.append("// deviate from (or lack) a module .uti blueprint: items embedded as full")
    lines.append("// structs in stores / creature inventories / placed containers. Consulted")
    lines.append("// by ForgeIsItemIllegal (forge_inc.nss) so legal loot never jails a player.")
    lines.append("// Re-run the generator after editing store/creature/container items.")
    lines.append("")
    lines.append("// Fixed-width fingerprint tuple for one permanent property; padding makes")
    lines.append("// the NWScript lexicographic sort agree with the generator's numeric sort.")
    lines.append("// Normalization must mirror gen-forge-legal.py's normalize_prop().")
    lines.append("string ForgeLegalPad5(int n)")
    lines.append("{")
    lines.append("    if (n < 0) n = 65535; // engine signals \"none\" as -1; GFF stores 65535")
    lines.append("    string s = IntToString(n);")
    lines.append("    while (GetStringLength(s) < 5)")
    lines.append("        s = \"0\" + s;")
    lines.append("    return s;")
    lines.append("}")
    lines.append("")
    lines.append("// TRUE when fixed-width tuple sA sorts before sB. NWScript has no string")
    lines.append("// ordering operators, so compare the four zero-padded numeric fields —")
    lines.append("// equivalent to the generator's lexicographic sort on these strings.")
    lines.append("int ForgeLegalTupleLess(string sA, string sB)")
    lines.append("{")
    lines.append("    int i;")
    lines.append("    for (i = 0; i < 4; i++)")
    lines.append("    {")
    lines.append("        int nA = StringToInt(GetSubString(sA, i * 6, 5));")
    lines.append("        int nB = StringToInt(GetSubString(sB, i * 6, 5));")
    lines.append("        if (nA != nB)")
    lines.append("            return nA < nB;")
    lines.append("    }")
    lines.append("    return FALSE;")
    lines.append("}")
    lines.append("")
    lines.append("// Runtime fingerprint of oItem: resref|t:s:c:p,... ascending, permanent")
    lines.append("// properties only (matches ForgeCountProps). Insertion sort via string scan.")
    lines.append("string ForgeLegalFingerprint(object oItem)")
    lines.append("{")
    lines.append("    string sBody = \"\";")
    lines.append("    itemproperty ip = GetFirstItemProperty(oItem);")
    lines.append("    while (GetIsItemPropertyValid(ip))")
    lines.append("    {")
    lines.append("        // Cosmetic props (visual effects, Light) are excluded, matching")
    lines.append("        // forge_inc's ForgeIsCosmeticProp and the generator.")
    lines.append("        int nPropType = GetItemPropertyType(ip);")
    lines.append("        if (GetItemPropertyDurationType(ip) == DURATION_TYPE_PERMANENT")
    lines.append("            && nPropType != ITEM_PROPERTY_VISUALEFFECT")
    lines.append("            && nPropType != ITEM_PROPERTY_LIGHT)")
    lines.append("        {")
    lines.append("            int nP1 = GetItemPropertyParam1(ip);")
    lines.append("            int nPV;")
    lines.append("            if (nP1 < 0 || nP1 == 255)")
    lines.append("                nPV = 65535; // no param1 slot on this property")
    lines.append("            else")
    lines.append("                nPV = GetItemPropertyParam1Value(ip);")
    lines.append("            string sTuple = ForgeLegalPad5(GetItemPropertyType(ip))")
    lines.append("                + \":\" + ForgeLegalPad5(GetItemPropertySubType(ip))")
    lines.append("                + \":\" + ForgeLegalPad5(GetItemPropertyCostTableValue(ip))")
    lines.append("                + \":\" + ForgeLegalPad5(nPV);")
    lines.append("            // insert sTuple into sBody keeping ascending order")
    lines.append("            int nLen = GetStringLength(sBody);")
    lines.append("            int nTuple = GetStringLength(sTuple);")
    lines.append("            int nPos = 0;")
    lines.append("            int bPlaced = FALSE;")
    lines.append("            string sNew = \"\";")
    lines.append("            while (nPos < nLen)")
    lines.append("            {")
    lines.append("                string sAt = GetSubString(sBody, nPos, nTuple);")
    lines.append("                if (!bPlaced && ForgeLegalTupleLess(sTuple, sAt))")
    lines.append("                {")
    lines.append("                    sNew += sTuple + \",\";")
    lines.append("                    bPlaced = TRUE;")
    lines.append("                }")
    lines.append("                sNew += sAt + \",\";")
    lines.append("                nPos += nTuple + 1;")
    lines.append("            }")
    lines.append("            if (!bPlaced)")
    lines.append("                sNew += sTuple + \",\";")
    lines.append("            sBody = sNew;")
    lines.append("        }")
    lines.append("        ip = GetNextItemProperty(oItem);")
    lines.append("    }")
    lines.append("    // strip trailing comma")
    lines.append("    int nBody = GetStringLength(sBody);")
    lines.append("    if (nBody > 0)")
    lines.append("        sBody = GetStringLeft(sBody, nBody - 1);")
    lines.append("    return GetResRef(oItem) + \"|\" + sBody;")
    lines.append("}")

    for i, chunk in enumerate(chunks):
        lines.append("")
        lines.append("int ForgeLegalChunk%d(string sFP)" % i)
        lines.append("{")
        for fp in chunk:
            lines.append("    if (sFP == \"%s\") return TRUE;" % fp)
        lines.append("    return FALSE;")
        lines.append("}")

    lines.append("")
    lines.append("// TRUE when oItem matches a known legally-placed variant. Only consulted")
    lines.append("// for items already over the legal caps and deviating from blueprint, so")
    lines.append("// a linear chunk scan is cheap enough.")
    lines.append("int ForgeIsKnownLegalVariant(object oItem)")
    lines.append("{")
    lines.append("    string sFP = ForgeLegalFingerprint(oItem);")
    for i in range(len(chunks)):
        lines.append("    if (ForgeLegalChunk%d(sFP)) return TRUE;" % i)
    lines.append("    return FALSE;")
    lines.append("}")
    lines.append("")

    OUTPUT.write_text("\n".join(lines))
    print("wrote %s (%d lines, %d chunk functions)"
          % (OUTPUT.relative_to(REPO), len(lines), len(chunks)))


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Staged forge-disenchant integrity check (build-time smoke test).

The three anvil forge dialogs (Tagget / Kimli / Bellnius) carry a generated
"staged disenchant" subtree (bin/inject_forge_disenchant.py): the player plans
which enchantments to strike and the smith only commits once the planned result
would be lawful, so a forge can never mint contraband. This check enforces the
subtree's wiring so a bad regen or hand-edit can't silently break it (a missing
gate or token would let an illegal item through, or a broken child link would
make the engine refuse to load the whole conversation).

It also guards that the Forge Warden's jail dialog still uses the immediate
forge_dis_* scripts and was NOT switched to the staged forge_stg_* ones.

Scans unpacked/ directly. Exits 0 on success, 1 on any failure.
"""

import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
UNPACKED = os.path.join(ROOT, "unpacked")

ANVIL = ["forge_item_mid", "kimli_forge", "bellnius_smith", "kallrist_forge"]
WARDEN = "forge_warden"

REQUIRED_SCRIPTS = (
    ["forge_stg_anvil", "forge_stg_ok", "forge_stg_go", "forge_stg_cancel",
     "forge_stg_pgn", "forge_stg_pgp", "forge_stg_hasn", "forge_stg_hasp",
     "forge_anvil_ctx", "forge_anvil_clr", "forge_stg_open", "forge_can_mod"]
    + [f"forge_stg_t{n}" for n in range(8)]
    + [f"forge_stg_c{n}" for n in range(8)]      # paginated staged count gates
    + [f"forge_dis_c{n}" for n in range(8)]      # shared by the Warden's immediate menu
)


def load(name):
    with open(os.path.join(UNPACKED, f"{name}.dlg.json"), encoding="utf-8") as f:
        return json.load(f)


def text0(nd):
    return nd.get("Text", {}).get("value", {}).get("0", "") or ""


def script(nd):
    return (nd.get("Script", {}).get("value") or "")


def active(lnk):
    return (lnk.get("Active", {}).get("value") or "")


def idx(lnk):
    return lnk.get("Index", {}).get("value")


def ischild(lnk):
    return lnk.get("IsChild", {}).get("value", 0)


def links(nd, key):
    return nd.get(key, {}).get("value", [])


def check_anvil(name, errs):
    d = load(name)
    E = d["EntryList"]["value"]
    R = d["ReplyList"]["value"]

    d1s = [i for i, e in enumerate(E) if script(e) == "forge_stg_anvil"]
    if len(d1s) != 1:
        errs.append(f"{name}: expected exactly one forge_stg_anvil entry, found {len(d1s)}")
        return
    d1i = d1s[0]
    e1 = E[d1i]
    t = text0(e1)
    for tok in ("<CUSTOM6119>", "<CUSTOM100>"):
        if tok not in t:
            errs.append(f"{name}: D1 menu text missing {tok}")

    # Conversation cleanup wired to BOTH end hooks (no stale cached item/plan).
    for hook in ("EndConversation", "EndConverAbort"):
        got = d.get(hook, {}).get("value") or ""
        if got != "forge_anvil_clr":
            errs.append(f"{name}: {hook}={got!r}, want forge_anvil_clr")

    # The "modify / strip" reply (ReplyList[1]) refreshes item/cap tokens.
    if len(R) > 1 and script(R[1]) != "forge_anvil_ctx":
        errs.append(f"{name}: ReplyList[1] Script={script(R[1])!r}, want forge_anvil_ctx")

    # The strip-hook reply owns D1 (the single non-child link into it) and must run
    # forge_stg_open so the menu tokens are primed BEFORE D1's text renders — an
    # entry's own Actions Taken run too late, which left token 6119 unset on first
    # open ("<UNRECOGNIZED TOKEN>") and the slot labels one click stale.
    hook_idx = None
    for ri, r in enumerate(R):
        for l in links(r, "EntriesList"):
            if idx(l) == d1i and not ischild(l):
                hook_idx = ri
    if hook_idx is None:
        errs.append(f"{name}: no owning (non-child) reply links the D1 strip menu")
    elif script(R[hook_idx]) != "forge_stg_open":
        errs.append(f"{name}: strip-hook reply Script={script(R[hook_idx])!r}, "
                    f"want forge_stg_open")

    # Over-cap modify gate: the modify reply (ReplyList[1]) opens the add-enchant
    # confirm only via forge_can_mod, and routes over-cap single items (still gated
    # by isitemonanvil) to an OVERLIMIT entry whose only enabled reply is the strip
    # hook — so an item already at/over the cap can never enter the enchant flow.
    if len(R) > 1:
        r1_links = links(R[1], "EntriesList")
        if "forge_can_mod" not in [active(l) for l in r1_links]:
            errs.append(f"{name}: modify reply (ReplyList[1]) not re-gated on "
                        f"forge_can_mod (over-cap items still reach the enchant flow)")
        over = [l for l in r1_links if active(l) == "isitemonanvil"]
        if not over:
            errs.append(f"{name}: modify reply has no isitemonanvil route to the "
                        f"over-limit entry")
        elif hook_idx is not None:
            d4 = E[idx(over[0])]
            if hook_idx not in [idx(x) for x in links(d4, "RepliesList")]:
                errs.append(f"{name}: over-limit entry E[{idx(over[0])}] does not "
                            f"offer the strip hook reply")

    d1_links = links(e1, "RepliesList")
    actives = [active(l) for l in d1_links]

    # 8 paginated slot toggles: Active forge_stg_cN -> reply (Script forge_stg_tN,
    # text <CUSTOM611N>). Slot N maps to absolute property index page*8 + N.
    for n in range(8):
        if f"forge_stg_c{n}" not in actives:
            errs.append(f"{name}: D1 missing slot link Active=forge_stg_c{n}")
    for l in d1_links:
        m = re.fullmatch(r"forge_stg_c(\d)", active(l))
        if not m:
            continue
        n = int(m.group(1))
        rr = R[idx(l)]
        if script(rr) != f"forge_stg_t{n}":
            errs.append(f"{name}: slot {n} reply Script={script(rr)!r}, want forge_stg_t{n}")
        if f"<CUSTOM{6110 + n}>" not in text0(rr):
            errs.append(f"{name}: slot {n} reply text missing <CUSTOM{6110 + n}>")

    # Pagination: Next/Prev page replies gated by their conditionals.
    for cond, scr, label in (("forge_stg_hasn", "forge_stg_pgn", "next-page"),
                             ("forge_stg_hasp", "forge_stg_pgp", "prev-page")):
        pg = [l for l in d1_links if active(l) == cond]
        if not pg:
            errs.append(f"{name}: D1 missing {label} link Active={cond}")
        elif script(R[idx(pg[0])]) != scr:
            errs.append(f"{name}: {label} reply Script={script(R[idx(pg[0])])!r}, want {scr}")

    # Commit reply: gated by forge_stg_ok, leads to a D2 confirm whose 'Aye' runs forge_stg_go.
    commit = [l for l in d1_links if active(l) == "forge_stg_ok"]
    if not commit:
        errs.append(f"{name}: D1 missing commit link Active=forge_stg_ok")
    else:
        rc = R[idx(commit[0])]
        d2_links = links(rc, "EntriesList")
        if not d2_links:
            errs.append(f"{name}: commit reply does not lead to a confirm entry")
        else:
            d2 = E[idx(d2_links[0])]
            go = [R[idx(x)] for x in links(d2, "RepliesList")
                  if script(R[idx(x)]) == "forge_stg_go"]
            if not go:
                errs.append(f"{name}: confirm entry has no forge_stg_go reply")
            else:
                # Loop-fix: the committed strike must NOT return to the strip menu
                # (which used to re-ask forever). It links to a success entry whose
                # script is not the menu's forge_stg_anvil.
                go_tgt = links(go[0], "EntriesList")
                if not go_tgt:
                    errs.append(f"{name}: forge_stg_go reply leads nowhere")
                elif idx(go_tgt[0]) == d1i or script(E[idx(go_tgt[0])]) == "forge_stg_anvil":
                    errs.append(f"{name}: forge_stg_go loops back to the strip menu "
                                f"(should lead to a success entry)")

    # Cancel + commit scripts present somewhere in the reply list.
    rscripts = {script(r) for r in R}
    for s in ("forge_stg_cancel", "forge_stg_go"):
        if s not in rscripts:
            errs.append(f"{name}: no reply with Script={s}")

    # Dialog-integrity gate. The corruption mode that makes the engine refuse to
    # load a conversation is a NODE carrying link-only fields (IsChild/Index) — a
    # link object where a node belongs. Also flag any link index out of range.
    # (LinkComment is optional on child links — the stock dialogs omit it.)
    for nd in E:
        if "IsChild" in nd or "Index" in nd:
            errs.append(f"{name}: entry node carries link-only IsChild/Index field")
    for nd in R:
        if "IsChild" in nd or "Index" in nd:
            errs.append(f"{name}: reply node carries link-only IsChild/Index field")
    for e in E:
        for l in links(e, "RepliesList"):
            if not (0 <= (idx(l) if idx(l) is not None else -1) < len(R)):
                errs.append(f"{name}: entry RepliesList link index {idx(l)} out of range")
    for r in R:
        for l in links(r, "EntriesList"):
            if not (0 <= (idx(l) if idx(l) is not None else -1) < len(E)):
                errs.append(f"{name}: reply EntriesList link index {idx(l)} out of range")


def check_scripts(errs):
    for s in REQUIRED_SCRIPTS:
        if not os.path.exists(os.path.join(UNPACKED, f"{s}.nss")):
            errs.append(f"missing script source: {s}.nss")


def check_property_sets(errs):
    """The three property sets the forge distinguishes must stay distinct.

    Restrictions (use limitations) are not enchantments: counting them toward
    the cap AND offering them for removal is roadmap
    forge-restrictrion-properties-exploit - stripping a class/race lock freed a
    slot and made the gear usable by a character it was never meant for. Light
    is listed but free. Pricing and blueprint identity must keep the old full
    view, or every restricted stock drop reads as tampered and gets jailed.
    """
    path = os.path.join(UNPACKED, "forge_inc.nss")
    with open(path, encoding="utf-8") as f:
        src = f.read()

    def body(fn):
        m = re.search(r"^\w[\w ]*?\b" + fn + r"\s*\([^)]*\)\s*\n\{(.*?)^\}",
                      src, re.S | re.M)
        return m.group(1) if m else None

    for const in ("FORGE_SEL_COUNTED", "FORGE_SEL_REMOVABLE", "FORGE_SEL_PRICED"):
        if not re.search(r"const int %s\s*=" % const, src):
            errs.append(f"forge_inc: missing selector constant {const}")

    restr = body("ForgeIsRestrictionProp")
    if restr is None:
        errs.append("forge_inc: ForgeIsRestrictionProp is gone - restrictions "
                    "would be counted and strippable again")
    else:
        for c in ("ALIGNMENT_GROUP", "CLASS", "RACIAL_TYPE",
                  "SPECIFIC_ALIGNMENT", "TILESET"):
            if f"ITEM_PROPERTY_USE_LIMITATION_{c}" not in restr:
                errs.append(f"forge_inc: ForgeIsRestrictionProp does not cover "
                            f"USE_LIMITATION_{c}")

    detr = body("ForgeIsDetrimentalProp")
    if detr is None:
        errs.append("forge_inc: ForgeIsDetrimentalProp is gone - drawbacks "
                    "would be counted and strippable again "
                    "(smith-can-disenchant-negative-abilities)")
    else:
        for c in ("DECREASED_ABILITY_SCORE", "DECREASED_AC",
                  "DECREASED_ATTACK_MODIFIER", "DECREASED_DAMAGE",
                  "DECREASED_ENHANCEMENT_MODIFIER", "DECREASED_SAVING_THROWS",
                  "DECREASED_SAVING_THROWS_SPECIFIC", "DECREASED_SKILL_MODIFIER",
                  "DAMAGE_VULNERABILITY", "NO_DAMAGE", "WEIGHT_INCREASE",
                  "ARCANE_SPELL_FAILURE"):
            if f"ITEM_PROPERTY_{c}" not in detr:
                errs.append(f"forge_inc: ForgeIsDetrimentalProp does not cover "
                            f"ITEM_PROPERTY_{c}")

    cosm = body("ForgeIsCosmeticProp")
    if cosm is None:
        errs.append("forge_inc: ForgeIsCosmeticProp is gone")
    else:
        for c in ("ITEM_PROPERTY_VISUALEFFECT", "ITEM_PROPERTY_LIGHT"):
            if c not in cosm:
                errs.append(f"forge_inc: ForgeIsCosmeticProp no longer covers {c}")

    inset = body("ForgePropInSet")
    if inset is None:
        errs.append("forge_inc: ForgePropInSet is gone")
    else:
        # Drawbacks must leave BOTH the removable and the counted set: the
        # removable branch returns early, so each needs its own exclusion.
        removable, _, counted = inset.partition("if (ForgeIsCosmeticProp(ip))")
        if "ForgeIsDetrimentalProp" not in removable:
            errs.append("forge_inc: ForgePropInSet's REMOVABLE branch no longer "
                        "excludes drawbacks - a smith could strip them again")
        if "ForgeIsDetrimentalProp" not in counted:
            errs.append("forge_inc: ForgePropInSet's COUNTED branch no longer "
                        "excludes drawbacks - drawbacks would eat slots again")
        # Pricing and the blueprint fingerprint must NOT move: the PRICED branch
        # stays an unconditional TRUE. Narrowing it re-values every cursed piece
        # upward and can jail gear that is lawful today.
        if not re.search(r"if \(nSel == FORGE_SEL_PRICED\)\s*\n\s*return TRUE;",
                         inset):
            errs.append("forge_inc: ForgePropInSet's PRICED branch is no longer "
                        "an unconditional 'return TRUE' - pricing and "
                        "fingerprints must not move when counting rules change")
    for fn in ("ForgeCountPropsSel", "ForgeGetPropByIndexSel"):
        if body(fn) is None:
            errs.append(f"forge_inc: {fn} is gone")

    # Every enumeration must route through a selector. A hand-rolled
    # `permanent && !cosmetic` loop is exactly how the three sets drift apart.
    strays = [m.start() for m in re.finditer(r"!ForgeIsCosmeticProp\(", src)]
    allowed = body("ForgePropInSet") or ""
    if len([s for s in strays]) and "!ForgeIsCosmeticProp(" not in allowed:
        errs.append("forge_inc: ForgePropInSet no longer consults "
                    "ForgeIsCosmeticProp")
    extra = re.findall(r"DURATION_TYPE_PERMANENT\s*\n?\s*&&\s*!ForgeIsCosmeticProp",
                       src)
    if extra:
        errs.append(f"forge_inc: {len(extra)} inline 'permanent && !cosmetic' "
                    "enumeration(s) left - use ForgePropInSet instead")

    # Right selector in the right place.
    for fn, sel in (("ForgeItemDeviatesFromBlueprint", "FORGE_SEL_PRICED"),
                    ("ForgeRebuildValue", "FORGE_SEL_PRICED"),
                    ("ForgeDisenchantSetup", "FORGE_SEL_REMOVABLE"),
                    ("ForgeStageSetupCued", "FORGE_SEL_REMOVABLE"),
                    ("ForgeStageCommit", "FORGE_SEL_REMOVABLE")):
        b = body(fn)
        if b is None:
            errs.append(f"forge_inc: {fn} not found")
        elif sel not in b:
            errs.append(f"forge_inc: {fn} must enumerate with {sel}")

    # The strip list and the plan bits must index the SAME set, or a commit
    # removes a different property than the one the player ticked.
    b = body("ForgeProjectedValue")
    if b is None:
        errs.append("forge_inc: ForgeProjectedValue not found")
    else:
        if "FORGE_SEL_REMOVABLE" not in b or "FORGE_SEL_PRICED" not in b:
            errs.append("forge_inc: ForgeProjectedValue must index the removable "
                        "set and price the priced set")
    b = body("ForgeProjectedPropCount")
    if b is None:
        errs.append("forge_inc: ForgeProjectedPropCount not found")
    elif "FORGE_SEL_COUNTED" not in b or "FORGE_SEL_REMOVABLE" not in b:
        errs.append("forge_inc: ForgeProjectedPropCount must walk the removable "
                    "set but tally only counted properties")

    b = body("ForgeUnlistedNote")
    if b is None:
        errs.append("forge_inc: ForgeUnlistedNote is gone - players lose the "
                    "explanation for restrictions/Light not being in the list")
    elif "ForgeIsDetrimentalProp" not in b:
        errs.append("forge_inc: ForgeUnlistedNote must explain drawbacks too - "
                    "otherwise they simply vanish from the strip list with no "
                    "word of why")

    # Retroactive half: items stripped before the fix sit UNDER both caps, so
    # only this rule catches them.
    b = body("ForgeMissingBlueprintDrawback")
    if b is None:
        errs.append("forge_inc: ForgeMissingBlueprintDrawback is gone - items "
                    "stripped of their drawbacks before the fix go unnoticed")
    b = body("ForgeItemLegality")
    if b is None:
        errs.append("forge_inc: ForgeItemLegality not found")
    elif "ForgeMissingBlueprintDrawback" not in b:
        errs.append("forge_inc: ForgeItemLegality must consult "
                    "ForgeMissingBlueprintDrawback")


def check_light_note(errs):
    """The forge's own Light enchant must say it costs no slot."""
    for name in ANVIL:
        d = load(name)
        for nd in d["ReplyList"]["value"]:
            if script(nd) == "setproplight":
                if "does not count" not in text0(nd):
                    errs.append(f"{name}: the Light enchant reply must tell the "
                                f"player it does not count toward the limit")


def check_warden(errs):
    d = load(WARDEN)
    allnodes = d["EntryList"]["value"] + d["ReplyList"]["value"]
    scripts = {script(n) for n in allnodes}
    if not any(s.startswith("forge_dis_") for s in scripts):
        errs.append(f"{WARDEN}: lost its immediate-removal forge_dis_* scripts")
    leaked = sorted(s for s in scripts if s.startswith("forge_stg_"))
    if leaked:
        errs.append(f"{WARDEN}: unexpectedly references staged scripts {leaked}")


def main():
    errs = []
    for name in ANVIL:
        check_anvil(name, errs)
    check_scripts(errs)
    check_property_sets(errs)
    check_light_note(errs)
    check_warden(errs)

    if errs:
        print(f"[forge-disenchant] FAIL: {len(errs)} problem(s):", file=sys.stderr)
        for e in errs:
            print(f"  - {e}", file=sys.stderr)
        return 1
    print(f"[forge-disenchant] OK: staged disenchant wired in {len(ANVIL)} anvil "
          f"dialogs; Warden unchanged.")
    return 0


if __name__ == "__main__":
    sys.exit(main())

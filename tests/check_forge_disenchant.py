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

ANVIL = ["forge_item_mid", "kimli_forge", "bellnius_smith"]
WARDEN = "forge_warden"

REQUIRED_SCRIPTS = (
    ["forge_stg_anvil", "forge_stg_ok", "forge_stg_go", "forge_stg_cancel",
     "forge_stg_pgn", "forge_stg_pgp", "forge_stg_hasn", "forge_stg_hasp",
     "forge_anvil_ctx", "forge_anvil_clr"]
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

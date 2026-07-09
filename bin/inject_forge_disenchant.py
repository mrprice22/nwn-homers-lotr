#!/usr/bin/env python3
"""Inject the STAGED forge disenchant sub-conversation into the three forge dialogs.

The forge masters let a player PLAN which enchantments to strike from an
over-quality item and only commit the removals once the planned result would be
lawful — so the real item never passes through an illegal state (and the player
is never jailed mid-effort). The running worth and per-slot cues are computed by
forge_inc.nss (ForgeStageSetupCued) and rendered through custom tokens.

Appends a shared subtree to each anvil dialog (Tagget / Kimli / Bellnius):

  Entry D1  "<CUSTOM6119> Which enchantments shall I strike..."  (Script: forge_stg_anvil)
    -> 8 slot toggles <CUSTOM6110..6117>  (Active: forge_dis_cN, Script: forge_stg_tN)
         -> back to D1 (child link: re-show with refreshed cues)
    -> "Strike the planned enchantments now."  (Active: forge_stg_ok)  -> Entry D2 confirm
    -> "Never mind — leave it whole."          (Script: forge_stg_cancel)  -> ends
  Entry D2  confirm  "<CUSTOM6119> Shall I strike..."
    -> "Aye, strike them..."  (Script: forge_stg_go)  -> back to D1 (child)
    -> "No, let me reconsider."                        -> back to D1 (child)

and hooks a new reply "Strip enchantments..." (gated by isitemonanvil) into every
menu entry that already offers the "modify the item" reply (ReplyList[1]).

The commit reply is gated by forge_stg_ok, which is TRUE only when the planned
removals would bring the item within the lawful value/property ceiling — that is
what stops a forge from ever minting contraband.

Idempotent: a previously-injected subtree (old immediate-removal OR this staged
one) is detected and removed first, then the current subtree is appended. The
Forge Warden dialog is NOT in DIALOGS and is never touched (it keeps the
immediate-removal forge_dis_* scripts).
"""

import json
from pathlib import Path

DIALOGS = [
    "forge_item_mid.dlg.json",
    "kimli_forge.dlg.json",
    "bellnius_smith.dlg.json",
    "kallrist_forge.dlg.json",
]

# Markers identifying our D1 menu entry across versions (immediate or staged).
ANVIL_SCRIPTS = {"forge_dis_anvil", "forge_stg_anvil"}

HOOK_TEXT = "Strip enchantments from the item on the anvil to make it lawful. (no gold returned)"
D1_TEXT = ("<CUSTOM6119> Which enchantments shall I strike from the <CUSTOM100>? "
           "Choose as many as you need — nothing is unmade until you bid me "
           "strike, and I take no payment for the unmaking.")
D2_TEXT = ("<CUSTOM6119> Shall I strike the planned enchantments from your "
           "<CUSTOM100>? There is no undoing it.")
COMMIT_TEXT = "Strike the planned enchantments now."
CANCEL_TEXT = "Never mind — leave it whole."
YES_TEXT = "Aye, strike them. The magic is forfeit."
NO_TEXT = "No, let me reconsider."
MORE_TEXT = "Show me more enchantments."
PREV_TEXT = "Show the previous enchantments."
DONE_TEXT = ("It is done. Your <CUSTOM100> bears the law's blessing once more — no "
             "enchantment upon it now offends the law.")
THANKS_TEXT = "My thanks."
LEAVE_TEXT = "Leave it as it is."
# Shown when "modify" is chosen on an item already at/over the forge's value cap:
# offers ONLY the strip hook (no yes/no add-enchant flow that could only fail at
# commit). worth=104, cap=105 are primed by the forge_can_mod / isitemonanvil gate.
OVERLIMIT_TEXT = ("The <CUSTOM100> is already worth <CUSTOM104> gold — at or beyond "
                  "the <CUSTOM105> gold the law lets me bind into one piece. I'll not "
                  "add to it. I can only strike enchantments from it to bring it "
                  "within the law.")

# Cleanup script wired to both end-conversation hooks (mirrors forge_ward_clr):
# clears the cached anvil item + staged plan so a fresh conversation re-derives
# the live item and the status token never lingers as "<UNRECOGNIZED TOKEN>".
END_SCRIPT = "forge_anvil_clr"
# Refresh script set on the "modify / strip" reply so every entry into the forge
# re-primes the item/cap display tokens (the modify path used to set none).
CTX_SCRIPT = "forge_anvil_ctx"
# Script on the replies that OPEN the staged strip menu (the strip hook and the
# confirm screen's "reconsider"): primes the slot/status tokens BEFORE the D1 menu
# entry's text renders (an entry's own Actions Taken runs too late — token 6119
# showed as "<UNRECOGNIZED TOKEN>" on first open).
OPEN_SCRIPT = "forge_stg_open"
# Gate on the modify-confirm entry link: open the add-enchant flow only when the
# item still has value headroom to enchant upward; over-cap single items route to
# the OVERLIMIT entry instead of the yes/no add-enchant path.
MOD_GATE = "forge_can_mod"


def resref(v):
    return {"type": "resref", "value": v}


def locstring(text):
    return {"type": "cexolocstring", "value": {"0": text}}


def entry_text(nd):
    return nd.get("Text", {}).get("value", {}).get("0", "") or ""


def link(struct_id, index, active="", child=False):
    d = {
        "__struct_id": struct_id,
        "Active": resref(active),
        "Index": {"type": "dword", "value": index},
        "IsChild": {"type": "byte", "value": 1 if child else 0},
    }
    if child:
        d["LinkComment"] = {"type": "cexostring", "value": ""}
    return d


def node(struct_id, text, script="", entry=False):
    d = {
        "__struct_id": struct_id,
        "Animation": {"type": "dword", "value": 0},
        "AnimLoop": {"type": "byte", "value": 1},
        "Comment": {"type": "cexostring", "value": ""},
        "Delay": {"type": "dword", "value": 4294967295},
        "Quest": {"type": "cexostring", "value": ""},
        "Script": resref(script),
        "Sound": resref(""),
        "Text": locstring(text),
    }
    if entry:
        d["Speaker"] = {"type": "cexostring", "value": ""}
        d["RepliesList"] = {"type": "list", "value": []}
    else:
        d["EntriesList"] = {"type": "list", "value": []}
    return d


def migrate(data) -> bool:
    """Remove any previously-injected subtree, returning the dialog to its
    pre-injection state. The injected nodes are always a contiguous tail block of
    both lists; the only edits to pre-existing nodes are the hook links appended
    to anchor entries. Returns True if a subtree was removed."""
    entries = data["EntryList"]["value"]
    replies = data["ReplyList"]["value"]

    d1 = next((i for i, e in enumerate(entries)
               if e.get("Script", {}).get("value") in ANVIL_SCRIPTS), None)
    if d1 is None:
        return False

    # First injected reply = smallest reply index linked from the D1 entry
    # (the slot replies / nevermind it owns).
    r_base = min(l["Index"]["value"]
                 for l in entries[d1]["RepliesList"]["value"])

    del entries[d1:]      # drop injected entries (D1, D2, D3, D4)
    del replies[r_base:]  # drop injected replies (slots, commit, cancel, yes/no, hook, leave)

    # Drop any link into the removed reply block (the hook links on anchors).
    for e in entries:
        e["RepliesList"]["value"] = [
            l for l in e["RepliesList"]["value"]
            if l["Index"]["value"] < r_base
        ]

    # Reverse the modify-path re-gate (see inject): a surviving reply (the modify
    # reply ReplyList[1]) may carry a link into the now-removed OVERLIMIT entry and
    # a confirm link re-gated to MOD_GATE. Drop the dangling link and restore the
    # original isitemonanvil gate so re-injection starts from the pristine routing.
    for r in replies:
        el = r.get("EntriesList", {}).get("value")
        if not el:
            continue
        changed = False
        kept = []
        for l in el:
            if l["Index"]["value"] >= d1:
                changed = True          # link into the removed injected entry block
                continue
            if l.get("Active", {}).get("value", "") == MOD_GATE:
                l["Active"] = resref("isitemonanvil")
                changed = True
            kept.append(l)
        if changed:
            for i, l in enumerate(kept):
                l["__struct_id"] = i
            r["EntriesList"]["value"] = kept
    return True


def inject(path: Path):
    data = json.loads(path.read_text())
    migrated = migrate(data)

    # Cleanup on both end-conversation hooks (was stock nw_walk_wp, which
    # forge_anvil_clr still calls so the smith walks back to its post).
    data["EndConversation"] = resref(END_SCRIPT)
    data["EndConverAbort"] = resref(END_SCRIPT)

    entries = data["EntryList"]["value"]
    replies = data["ReplyList"]["value"]

    # The "modify / strip" reply (ReplyList[1]) now refreshes the item/cap tokens
    # every time it is chosen, so the smith never speaks about a previously-worked
    # item or quotes a stale GP cap.
    if len(replies) > 1:
        replies[1]["Script"] = resref(CTX_SCRIPT)

    # Anchor entries: those whose RepliesList links the anvil-menu reply (index
    # 1, the "modify the item" link in all three dialogs).
    anchors = []
    for ei, e in enumerate(entries):
        for l in e["RepliesList"]["value"]:
            if l["Index"]["value"] == 1:
                anchors.append((ei, l.get("IsChild", {}).get("value", 0)))
                break
    if not anchors:
        raise SystemExit(f"{path.name}: no anchor entry links ReplyList[1]")

    # Forge hub to return to after a successful strike: the "Is there anything
    # else?" entry (present in all three dialogs), else the owning anchor.
    hub = anchors[0][0]
    for ei, _ in anchors:
        if "anything else" in entry_text(entries[ei]).lower():
            hub = ei
            break

    d1 = len(entries)        # disenchant menu entry
    d2 = d1 + 1              # confirm entry
    d3 = d1 + 2              # success entry (returns to the forge hub)
    d4 = d1 + 3              # "at the limit — strike only" entry (over-cap modify)
    r_slot0 = len(replies)   # 8 slot replies: r_slot0 .. r_slot0+7
    r_more = r_slot0 + 8     # "Show more enchantments"  (next page)
    r_prev = r_slot0 + 9     # "Show previous enchantments"
    r_commit = r_slot0 + 10
    r_cancel = r_slot0 + 11
    r_yes = r_slot0 + 12
    r_no = r_slot0 + 13
    r_thanks = r_slot0 + 14  # D3 "My thanks." -> hub
    r_hook = r_slot0 + 15
    r_leave = r_slot0 + 16   # D4 "Leave it as it is." -> hub

    # Entry D1: 8 paginated slot toggles + page nav + commit + cancel.
    e1 = node(d1, D1_TEXT, script="forge_stg_anvil", entry=True)
    for n in range(8):
        e1["RepliesList"]["value"].append(
            link(n, r_slot0 + n, active=f"forge_stg_c{n}"))
    e1["RepliesList"]["value"].append(link(8, r_more, active="forge_stg_hasn"))
    e1["RepliesList"]["value"].append(link(9, r_prev, active="forge_stg_hasp"))
    e1["RepliesList"]["value"].append(link(10, r_commit, active="forge_stg_ok"))
    e1["RepliesList"]["value"].append(link(11, r_cancel))

    # Entry D2: confirm yes/no.
    e2 = node(d2, D2_TEXT, entry=True)
    e2["RepliesList"]["value"].append(link(0, r_yes))
    e2["RepliesList"]["value"].append(link(1, r_no))

    # Entry D3: success line shown after a committed strike.
    e3 = node(d3, DONE_TEXT, entry=True)
    e3["RepliesList"]["value"].append(link(0, r_thanks))

    # Entry D4: shown when "modify" is chosen on an item already at/over the forge's
    # value cap. Offers ONLY the strip hook (gated by isitemonanvil) plus "leave it"
    # — never the yes/no add-enchant flow, which could only fail at commit.
    e4 = node(d4, OVERLIMIT_TEXT, entry=True)
    e4["RepliesList"]["value"].append(
        link(0, r_hook, active="isitemonanvil", child=True))
    e4["RepliesList"]["value"].append(link(1, r_leave, child=True))

    new_replies = []
    # Slot toggles: each re-shows D1 (child link) so the cues refresh.
    for n in range(8):
        r = node(r_slot0 + n, f"<CUSTOM{6110 + n}>", script=f"forge_stg_t{n}")
        r["EntriesList"]["value"].append(link(0, d1, child=True))
        new_replies.append(r)

    # Page navigation: both re-show D1 with the new page's cues (child link).
    r = node(r_more, MORE_TEXT, script="forge_stg_pgn")
    r["EntriesList"]["value"].append(link(0, d1, child=True))
    new_replies.append(r)
    r = node(r_prev, PREV_TEXT, script="forge_stg_pgp")
    r["EntriesList"]["value"].append(link(0, d1, child=True))
    new_replies.append(r)

    # Commit reply: navigation only (the actual removal runs from D2's "Aye").
    # Owns D2.
    r = node(r_commit, COMMIT_TEXT)
    r["EntriesList"]["value"].append(link(0, d2))
    new_replies.append(r)

    # Cancel reply: clears the plan and ends (no entry link).
    new_replies.append(node(r_cancel, CANCEL_TEXT, script="forge_stg_cancel"))

    # D2 "Aye": commit, then to the success line D3 (NOT back to the strip menu,
    # which looped forever). Owns D3.
    r = node(r_yes, YES_TEXT, script="forge_stg_go")
    r["EntriesList"]["value"].append(link(0, d3))
    new_replies.append(r)

    # D2 "No": back to D1, no change. Re-primes the menu tokens before D1 re-renders.
    r = node(r_no, NO_TEXT, script=OPEN_SCRIPT)
    r["EntriesList"]["value"].append(link(0, d1, child=True))
    new_replies.append(r)

    # D3 "My thanks": return to the forge hub ("Is there anything else?").
    r = node(r_thanks, THANKS_TEXT)
    r["EntriesList"]["value"].append(link(0, hub, child=True))
    new_replies.append(r)

    # Hook reply: owns D1 (the one non-child link to it). Its Script primes the
    # menu tokens before D1's text renders (fixes the "<UNRECOGNIZED TOKEN>" open).
    r = node(r_hook, HOOK_TEXT, script=OPEN_SCRIPT)
    r["EntriesList"]["value"].append(link(0, d1))
    new_replies.append(r)

    # D4 "Leave it as it is": return to the forge hub, item untouched.
    r = node(r_leave, LEAVE_TEXT)
    r["EntriesList"]["value"].append(link(0, hub, child=True))
    new_replies.append(r)

    entries.extend([e1, e2, e3, e4])
    replies.extend(new_replies)

    # Hook the new reply into every anchor menu entry. The entry that owns
    # ReplyList[1] (IsChild=0) owns the hook too; others get child links.
    for ei, ischild in anchors:
        rl = entries[ei]["RepliesList"]["value"]
        rl.append(link(len(rl), r_hook, active="isitemonanvil",
                       child=(ischild == 1)))

    # Re-gate the modify-confirm entry: open the add-enchant flow only when the
    # item still has value headroom (MOD_GATE); route over-cap single items to the
    # OVERLIMIT entry D4 (still gated by isitemonanvil, evaluated immediately after,
    # so a no/multiple-item case falls through to the dialog's own fallback).
    r1_links = replies[1]["EntriesList"]["value"]
    for i, l in enumerate(r1_links):
        if l.get("Active", {}).get("value", "") == "isitemonanvil":
            l["Active"] = resref(MOD_GATE)
            r1_links.insert(i + 1, link(0, d4, active="isitemonanvil"))
            break
    else:
        raise SystemExit(f"{path.name}: modify reply (ReplyList[1]) has no "
                         f"isitemonanvil-gated confirm link to re-gate")
    for i, l in enumerate(r1_links):
        l["__struct_id"] = i

    path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n")
    verb = "re-injected (migrated)" if migrated else "injected"
    print(f"{path.name}: {verb} (D1=entry {d1}, D2=entry {d2}, D3=entry {d3}, "
          f"D4=entry {d4}, replies {r_slot0}..{r_leave}, hub=entry {hub}, "
          f"anchors {[a for a, _ in anchors]})")


def main():
    root = Path(__file__).resolve().parent.parent / "unpacked"
    for name in DIALOGS:
        inject(root / name)


if __name__ == "__main__":
    main()

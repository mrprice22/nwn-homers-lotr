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

# Cleanup script wired to both end-conversation hooks (mirrors forge_ward_clr):
# clears the cached anvil item + staged plan so a fresh conversation re-derives
# the live item and the status token never lingers as "<UNRECOGNIZED TOKEN>".
END_SCRIPT = "forge_anvil_clr"
# Refresh script set on the "modify / strip" reply so every entry into the forge
# re-primes the item/cap display tokens (the modify path used to set none).
CTX_SCRIPT = "forge_anvil_ctx"


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

    del entries[d1:]      # drop injected entries (D1, D2)
    del replies[r_base:]  # drop injected replies (slots, commit, cancel, yes/no, hook)

    # Drop any link into the removed reply block (the hook links on anchors).
    for e in entries:
        e["RepliesList"]["value"] = [
            l for l in e["RepliesList"]["value"]
            if l["Index"]["value"] < r_base
        ]
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
    r_slot0 = len(replies)   # 8 slot replies: r_slot0 .. r_slot0+7
    r_more = r_slot0 + 8     # "Show more enchantments"  (next page)
    r_prev = r_slot0 + 9     # "Show previous enchantments"
    r_commit = r_slot0 + 10
    r_cancel = r_slot0 + 11
    r_yes = r_slot0 + 12
    r_no = r_slot0 + 13
    r_thanks = r_slot0 + 14  # D3 "My thanks." -> hub
    r_hook = r_slot0 + 15

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

    # D2 "No": back to D1, no change.
    r = node(r_no, NO_TEXT)
    r["EntriesList"]["value"].append(link(0, d1, child=True))
    new_replies.append(r)

    # D3 "My thanks": return to the forge hub ("Is there anything else?").
    r = node(r_thanks, THANKS_TEXT)
    r["EntriesList"]["value"].append(link(0, hub, child=True))
    new_replies.append(r)

    # Hook reply: owns D1 (the one non-child link to it).
    r = node(r_hook, HOOK_TEXT)
    r["EntriesList"]["value"].append(link(0, d1))
    new_replies.append(r)

    entries.extend([e1, e2, e3])
    replies.extend(new_replies)

    # Hook the new reply into every anchor menu entry. The entry that owns
    # ReplyList[1] (IsChild=0) owns the hook too; others get child links.
    for ei, ischild in anchors:
        rl = entries[ei]["RepliesList"]["value"]
        rl.append(link(len(rl), r_hook, active="isitemonanvil",
                       child=(ischild == 1)))

    path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n")
    verb = "re-injected (migrated)" if migrated else "injected"
    print(f"{path.name}: {verb} (D1=entry {d1}, D2=entry {d2}, D3=entry {d3}, "
          f"replies {r_slot0}..{r_hook}, hub=entry {hub}, "
          f"anchors {[a for a, _ in anchors]})")


def main():
    root = Path(__file__).resolve().parent.parent / "unpacked"
    for name in DIALOGS:
        inject(root / name)


if __name__ == "__main__":
    main()

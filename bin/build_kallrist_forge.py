#!/usr/bin/env python3
"""Build kallrist_forge.dlg.json — the Kallrist Crypt signature forge dialog.

The Kallrist Crypt forge is the fourth Forge of Wonders (see CLAUDE.md / the
forge memory). It is a small, SPECIALIZED forge: unlike the other three, it does
NOT offer the shared enchant menu at all. It sits at the top legal cap (6 props /
750k, like Moria) but its whole menu is the crypt/undeath signature options the
other forges lack.

This script derives the dialog from the top-tier Bellnius (Moria) forge dialog
(so it inherits the greeting / shared calcmodvalue1 confirm scaffolding), then
strips the entire shared enchant menu down to the signature-only offerings:

  * strips the staged-disenchant subtree (re-appended afterwards by
    inject_forge_disenchant.py, which must list kallrist_forge in DIALOGS);
  * adds a "Death Magic" leaf to the Miscellaneous Immunity submenu
    (setpropmiscimmun already selected there -> new setimmundeath param) — Deathless;
  * adds a new top-level "Spell Immunity" category (setspellimmun) leading to
    an "Implosion" leaf (setimplosion) — the module's AI casts SPELL_IMPLOSION as
    an instant-death effect, so warding it is meaningful — Voidshield;
  * reflavors the existing Paralysis immunity leaf to advertise that it also wards
    the crypt's petrifying gazes (EffectPetrify is a paralyze-family effect in
    NWN:EE, so Paralysis immunity blocks basilisk/medusa petrification) — Unbroken;
  * adds a unique offensive option: a Negative-Energy Damage Bonus category
    (setdampropneg sets MODIFY_PROPERTY="Damage Bonus" + MODIFY_PARAM2=NEGATIVE)
    leading to a dice submenu with 5 choices (setdam4 / setdam2d4 / setdam1d6 /
    setdam1d10 / setdam1d12 -> MODIFY_PARAM3). No other forge offers negative-energy
    damage. itemprocs.nss builds ItemPropertyDamageBonus(PARAM2, PARAM3) unchanged.
    The menu link is gated isweaponorglove;
  * adds the matching defensive option: a Negative-Energy Damage RESISTANCE category
    (setpropresneg sets MODIFY_PROPERTY="Damage Resistance" + MODIFY_PARAM2=NEGATIVE)
    leading to a submenu of the five stock rungs (setdamresist25/20/15/10/05 ->
    MODIFY_PARAM3). No other forge offers negative-energy resistance either - Moria's
    resistance menu carries only the eight stock damage types. The menu link is gated
    isnotweapon, so it is offered on worn gear only (armour, shields, helms, cloaks,
    boots, bracers, belts, rings, amulets);
  * PRUNES the main menu to keep only the two immunity categories + the new
    negative-energy category, and prunes the immunity submenu to the two wardings
    (Death Magic + Paralysis). The now-orphaned shared-enchant category nodes stay
    in the lists (unreachable, harmless) so existing node INDICES are preserved and
    inject_forge_disenchant.py — which keys off reply index 1 — still works.

Every leaf routes to the dialog's shared calcmodvalue1 confirm entry, so pricing /
cap enforcement / apply are reused unchanged (GetNewProperty in itemprocs.nss
dispatches "Spell Immunity Specific" -> ItemPropertySpellImmunitySpecific and
"Damage Bonus" -> ItemPropertyDamageBonus).

Idempotent: rebuilding from the same Moria source reproduces the file.

Run:  python3 bin/build_kallrist_forge.py
      # then ensure kallrist_forge is in inject_forge_disenchant.py DIALOGS and run it
"""
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from inject_forge_disenchant import migrate, node, link  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent / "unpacked"
SRC = ROOT / "bellnius_smith.dlg.json"
DST = ROOT / "kallrist_forge.dlg.json"


def rtext(nd):
    return (nd.get("Text", {}).get("value", {}) or {}).get("0", "") or ""


def locstr(text):
    return {"type": "cexolocstring", "value": {"0": text}}


def main():
    d = json.loads(SRC.read_text())
    migrate(d)  # return to the pristine (pre-disenchant-subtree) dialog
    E = d["EntryList"]["value"]
    R = d["ReplyList"]["value"]

    # Locate the anchor nodes by content, robust to index drift.
    e_menu = next(i for i, e in enumerate(E)
                  if rtext(e).strip().lower().startswith("what type of modification"))
    e_immun = next(i for i, e in enumerate(E)
                   if rtext(e).strip().lower().startswith("select an immunity type"))
    e_calc = next(i for i, e in enumerate(E)
                  if (e.get("Script", {}).get("value") or "") == "calcmodvalue1")

    # Reflavor the Paralysis immunity leaf so players know it wards petrification.
    r_para = next(i for i, r in enumerate(R)
                  if (r.get("Script", {}).get("value") or "") == "setimmunparalyze")
    R[r_para]["Text"] = locstr(
        "Paralysis — and the petrifying gaze of basilisk and medusa.")

    # New node indices (computed before any append; appends must follow this order).
    e_si = len(E)          # new "Spell Immunity" submenu entry
    e_dice = e_si + 1      # new negative-energy dice submenu entry
    e_res = e_si + 2       # new negative-energy resistance submenu entry
    r_dm = len(R)          # Death Magic leaf (added to the immunity submenu)
    r_sc = r_dm + 1        # Spell-Immunity category reply (main menu)
    r_impl = r_dm + 2      # Implosion leaf (Spell Immunity submenu)
    r_negcat = r_dm + 3    # Negative-Energy Damage category reply (main menu)
    # Five dice leaves (dice submenu) -> shared confirm.
    r_d4 = r_dm + 4        # +4 flat
    r_d2d4 = r_dm + 5      # 2d4
    r_d1d6 = r_dm + 6      # 1d6
    r_d1d10 = r_dm + 7     # 1d10
    r_d1d12 = r_dm + 8     # 1d12
    r_rescat = r_dm + 9    # Negative-Energy Resistance category reply (main menu)
    # Five resistance leaves (resistance submenu) -> shared confirm.
    r_r25 = r_dm + 10      # Resist 25
    r_r20 = r_dm + 11      # Resist 20
    r_r15 = r_dm + 12      # Resist 15
    r_r10 = r_dm + 13      # Resist 10
    r_r05 = r_dm + 14      # Resist 5

    # --- Signature immunity leaves (Death Magic + Spell Immunity/Implosion) ---
    # Death Magic leaf (Deathless) -> shared confirm (child link, like stock leaves).
    nd = node(r_dm, "Death Magic — the tomb's own art, turned against you.",
              script="setimmundeath")
    nd["EntriesList"]["value"].append(link(0, e_calc, child=True))
    R.append(nd)

    # Spell-Immunity category reply (Voidshield) -> new submenu entry.
    nd = node(r_sc, "Spell Immunity.", script="setspellimmun")
    nd["EntriesList"]["value"].append(link(0, e_si))
    R.append(nd)

    # New Spell Immunity submenu entry + its Implosion leaf.
    ne = node(e_si, "Against which spell shall the crypt ward you?", entry=True)
    ne["RepliesList"]["value"].append(link(0, r_impl))
    E.append(ne)
    nd = node(r_impl, "Implosion — the void that folds flesh inward.",
              script="setimplosion")
    nd["EntriesList"]["value"].append(link(0, e_calc, child=True))
    R.append(nd)

    # --- Signature offensive option: Negative-Energy Damage Bonus ---
    # No other forge offers negative-energy damage. The category script sets both
    # MODIFY_PROPERTY="Damage Bonus" and MODIFY_PARAM2=IP_CONST_DAMAGETYPE_NEGATIVE;
    # the dice leaves set MODIFY_PARAM3, then route to the shared confirm exactly
    # like the stock damage-dice leaves. itemprocs.nss builds
    # ItemPropertyDamageBonus(PARAM2, PARAM3) unchanged.
    nd = node(r_negcat,
              "Negative-Energy Damage — the grave's own chill, bound to the edge.",
              script="setdampropneg")
    nd["EntriesList"]["value"].append(link(0, e_dice))
    R.append(nd)

    ne = node(e_dice, "How deep shall the grave-chill bite?", entry=True)
    dice = [(r_d4, "setdam4", "+4."),
            (r_d2d4, "setdam2d4", "2d4."),
            (r_d1d6, "setdam1d6", "1d6."),
            (r_d1d10, "setdam1d10", "1d10."),
            (r_d1d12, "setdam1d12", "1d12.")]
    for pos, (ri, scr, txt) in enumerate(dice):
        ne["RepliesList"]["value"].append(link(pos, ri))
    E.append(ne)
    for ri, scr, txt in dice:
        nd = node(ri, txt, script=scr)
        nd["EntriesList"]["value"].append(link(0, e_calc, child=True))
        R.append(nd)

    # --- Signature defensive option: Negative-Energy Damage Resistance -----
    # The mirror of the option above: the edge is for weapons, the ward is for
    # everything you wear. No other forge offers negative-energy resistance at
    # all - Moria's resistance menu carries only the eight stock damage types.
    # The category script sets both MODIFY_PROPERTY="Damage Resistance" and
    # MODIFY_PARAM2=IP_CONST_DAMAGETYPE_NEGATIVE, so the stock setdamresistNN
    # leaves supply MODIFY_PARAM3 unchanged and itemprocs.nss builds
    # ItemPropertyDamageResistance(PARAM2, PARAM3) with no code change. Pricing
    # is the engine value delta (calcmodvalue2), so Negative-resist costs exactly
    # what Moria charges for Fire-resist at the same rung.
    nd = node(r_rescat,
              "Negative-Energy Resistance — the grave's own chill, turned aside.",
              script="setpropresneg")
    nd["EntriesList"]["value"].append(link(0, e_res))
    R.append(nd)

    ne = node(e_res, "How much of the grave-chill shall be turned aside each round?",
              entry=True)
    # Bare numbers, matching the rung labels players already know from Moria's
    # resistance ladder (the dice submenu above keeps its own "+4." style).
    resist = [(r_r25, "setdamresist25", "25"),
              (r_r20, "setdamresist20", "20"),
              (r_r15, "setdamresist15", "15"),
              (r_r10, "setdamresist10", "10"),
              (r_r05, "setdamresist05", "5")]
    for pos, (ri, scr, txt) in enumerate(resist):
        ne["RepliesList"]["value"].append(link(pos, ri))
    E.append(ne)
    for ri, scr, txt in resist:
        nd = node(ri, txt, script=scr)
        nd["EntriesList"]["value"].append(link(0, e_calc, child=True))
        R.append(nd)

    # --- Prune to a signature-only menu ------------------------------------
    # The main menu keeps ONLY: Miscellaneous Immunity (-> wardings submenu), the
    # new Spell Immunity category, and the new Negative-Energy Damage category.
    # All other stock enchant categories are dropped from the reply list (their
    # nodes remain orphaned in R so existing indices — and inject_forge_disenchant's
    # reply-index-1 keying — are preserved).
    def script_of(reply_link):
        return (R[reply_link["Index"]["value"]].get("Script", {}).get("value") or "")

    keep_menu = [l for l in E[e_menu]["RepliesList"]["value"]
                 if script_of(l) == "setpropmiscimmun"]
    keep_menu.append(link(0, r_sc))       # Spell Immunity
    # Slot gating lives on the LINK, not on the reply node: the Active mirrored
    # on the top-level ReplyList node is stale in all four forge dialogs and is
    # ignored at runtime. The edge only makes sense on something you swing;
    # the ward only on something you wear.
    keep_menu.append(link(0, r_negcat, active="isweaponorglove"))
    keep_menu.append(link(0, r_rescat, active="isnotweapon"))
    for i, l in enumerate(keep_menu):
        l["__struct_id"] = i
    E[e_menu]["RepliesList"]["value"] = keep_menu

    # The wardings submenu keeps ONLY Paralysis (Unbroken) + the new Death Magic
    # (Deathless) leaf; the other stock immunity leaves are dropped.
    keep_immun = [l for l in E[e_immun]["RepliesList"]["value"]
                  if script_of(l) == "setimmunparalyze"]
    keep_immun.append(link(0, r_dm))      # Death Magic
    for i, l in enumerate(keep_immun):
        l["__struct_id"] = i
    E[e_immun]["RepliesList"]["value"] = keep_immun

    # --- Forge access gate: require the Horn of the Fell Beast in inventory ---
    # The forge is bound to the crypt guardian; only one bearing the horn looted
    # from it may use the anvil. A refusal entry sits at the TOP of the
    # StartingList, gated by fb_no_horn (TRUE when the PC lacks the horn); the
    # original greeting entries remain below as the fallback that fires for
    # horn-bearers. StartingList links carry __struct_id (their position) but no
    # IsChild, so they are built by hand rather than via link().
    e_refuse = len(E)
    E.append(node(
        e_refuse,
        "You do not bear the Horn of the Fell Beast. This forge was bound to the "
        "crypt's guardian; without its horn the anvil stays cold to your hand. "
        "Slay the beast, take up its horn, and return to me.",
        entry=True))
    old_start = d["StartingList"]["value"]
    new_start = [{
        "__struct_id": 0,
        "Active": {"type": "resref", "value": "fb_no_horn"},
        "Index": {"type": "dword", "value": e_refuse},
    }]
    for i, l in enumerate(old_start):
        l["__struct_id"] = i + 1
        new_start.append(l)
    d["StartingList"]["value"] = new_start

    DST.write_text(json.dumps(d, indent=2, ensure_ascii=False) + "\n")
    print(f"built {DST.name}: entries={len(E)} replies={len(R)} "
          f"(menu=E{e_menu} keeps {len(E[e_menu]['RepliesList']['value'])} categories, "
          f"immun=E{e_immun} keeps {len(E[e_immun]['RepliesList']['value'])} leaves, "
          f"calc=E{e_calc}, spellimmun=E{e_si}, dice=E{e_dice}, "
          f"deathmagic=R{r_dm}, spellcat=R{r_sc}, implosion=R{r_impl}, "
          f"negcat=R{r_negcat}, dice=R{r_d4}..R{r_d1d12}, resist=E{e_res}, "
          f"rescat=R{r_rescat}, rungs=R{r_r25}..R{r_r05})")


if __name__ == "__main__":
    main()

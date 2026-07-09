#!/usr/bin/env python3
"""Build kallrist_forge.dlg.json — the Kallrist Crypt signature forge dialog.

The Kallrist Crypt forge is the fourth Forge of Wonders (see CLAUDE.md / the
forge memory). It sits at the top legal cap (6 props / 750k, like Moria) but is
distinguished by a crypt/undeath SIGNATURE immunity menu the other three forges
do not offer.

This script derives the dialog from the top-tier Bellnius (Moria) forge dialog so
it inherits the full high-tier enchant menu, then:

  * strips the staged-disenchant subtree (re-appended afterwards by
    inject_forge_disenchant.py, which must list kallrist_forge in DIALOGS);
  * adds a "Death Magic" leaf to the Miscellaneous Immunity submenu
    (setpropmiscimmun already selected there -> new setimmundeath param);
  * adds a new top-level "Spell Immunity" category (setspellimmun) leading to
    an "Implosion" leaf (setimplosion) — the module's AI casts SPELL_IMPLOSION as
    an instant-death effect, so warding it is meaningful;
  * reflavors the existing Paralysis immunity leaf to advertise that it also wards
    the crypt's petrifying gazes (EffectPetrify is a paralyze-family effect in
    NWN:EE, so Paralysis immunity blocks basilisk/medusa petrification).

Every new leaf routes to the dialog's shared calcmodvalue1 confirm entry exactly
like the stock immunity leaves, so pricing / cap enforcement / apply are reused
unchanged (GetNewProperty in itemprocs.nss dispatches the new
"Spell Immunity Specific" property to ItemPropertySpellImmunitySpecific).

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

    # New node indices (computed before any append; appends follow this order).
    e_si = len(E)          # new "Spell Immunity" submenu entry
    r_dm = len(R)          # Death Magic leaf (added to the immunity submenu)
    r_sc = r_dm + 1        # Spell-Immunity category reply (added to the main menu)
    r_impl = r_dm + 2      # Implosion leaf (added to the new submenu)

    # Death Magic leaf -> shared confirm entry (child link, like stock leaves).
    nd = node(r_dm, "Death Magic — the tomb's own art, turned against you.",
              script="setimmundeath")
    nd["EntriesList"]["value"].append(link(0, e_calc, child=True))
    R.append(nd)
    rl = E[e_immun]["RepliesList"]["value"]
    rl.append(link(len(rl), r_dm))

    # Spell-Immunity category reply on the main menu -> new submenu entry.
    nd = node(r_sc, "Spell Immunity.", script="setspellimmun")
    nd["EntriesList"]["value"].append(link(0, e_si))
    R.append(nd)
    rl = E[e_menu]["RepliesList"]["value"]
    rl.append(link(len(rl), r_sc))

    # New submenu entry + its Implosion leaf.
    ne = node(e_si, "Against which spell shall the crypt ward you?", entry=True)
    ne["RepliesList"]["value"].append(link(0, r_impl))
    E.append(ne)
    nd = node(r_impl, "Implosion — the void that folds flesh inward.",
              script="setimplosion")
    nd["EntriesList"]["value"].append(link(0, e_calc, child=True))
    R.append(nd)

    DST.write_text(json.dumps(d, indent=2, ensure_ascii=False) + "\n")
    print(f"built {DST.name}: entries={len(E)} replies={len(R)} "
          f"(menu=E{e_menu}, immun=E{e_immun}, calc=E{e_calc}, spellimmun=E{e_si}, "
          f"deathmagic=R{r_dm}, spellcat=R{r_sc}, implosion=R{r_impl})")


if __name__ == "__main__":
    main()

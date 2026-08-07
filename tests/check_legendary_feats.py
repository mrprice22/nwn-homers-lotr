#!/usr/bin/env python3
"""Build gate: hak_2da/feat.2da must stay the stock table plus our rows.

feat.2da is the one 2DA in lotr_rules.hak that carries content rather than
tuning, and four things can break it silently:

1. **The wrong base table.** The module resolves the **stock** feat.2da — 1116
   rows (0-1115, last PLAYER_TOOL_10), 43 columns. hak_2da/feat.2da used to hold
   a byte-identical copy of the table inside `cep2_add_feats.hak`, **a hak
   Mod_HakList does not load**: 24,771 rows and 44 columns. Shipping that would
   add ~23,000 CEP weapon-of-choice feats to every character's feat list and
   change the column count under every row.
2. **A re-extraction over the generated file.** Pulling a fresh feat.2da out of
   the game data drops every legendary row, and the only symptom is that a
   granted feat stops existing — the character sheet shows a blank entry.
   bin/gen-legendary-feats.py --from-stock is the supported way to swap the base.
3. **A legendary feat reachable from the engine's own level-up page.** The
   picker is the only grant path; a feat the level-up page can also offer is a
   double-grant. ALLCLASSESCANUSE must be 0 on every owned row, and no
   cls_feat_*.2da may list one.
4b. **A stock feat we reworked reverting to its shipped description.** All 40
   Devastating Critical rows point at our TLK, because the Bioware text says the
   target must save or die and the module has not worked that way since the
   devcrit-roll rework. A re-extraction restores the original strref and the
   only symptom is a feat describing a rule that no longer exists.
4. **Rows and TLK strings drifting apart.** Each row's NAME and DESCRIPTION are
   strrefs into our custom TLK. This gate re-derives them from
   bin/gen-legendary-feats.py, which derives them from where bin/build-lotr-tlk
   actually places the strings — so a row pointing at the wrong string fails
   here rather than showing the wrong tooltip in game.

It does NOT check the packed hak: a correct feat.2da that was never packed into
lotr_rules.hak is still dead in game (`bin/build-lotr-rules-hak` verifies its own
output), and it does not check that the strings reached the installed TLK —
that is tests/check_lotr_tlk.py's job.

Exit 0 = coherent, 1 = drifted.
"""
import importlib.util
import json
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
GENERATOR = REPO / "bin" / "gen-legendary-feats.py"
FEAT_2DA = REPO / "hak_2da" / "feat.2da"
HAK_BUILDER = REPO / "bin" / "build-lotr-rules-hak"
HAK_2DA_DIR = REPO / "hak_2da"
UNPACKED = REPO / "unpacked"
IDS_INC = UNPACKED / "legfeat_ids_inc.nss"
MODULE_LOAD = UNPACKED / "onmoduleload.nss"
CLIENT_ENTER = UNPACKED / "mod_cliententer.nss"
# Where a rest actually completes in this module: the engine's own rest is
# cancelled at REST_STARTED to open the rest menu, so ForceRest is the path a
# player reaches. on_mod_rest keeps a REST_FINISHED hook as a fallback.
REST_HOOKS = [
    UNPACKED / "ew_forcerest.nss",
    UNPACKED / "forcerest.nss",
]
REST_DLG = UNPACKED / "emotewand.dlg.json"
RESPEC_DLG = UNPACKED / "_pc_builder_v1.dlg.json"
LEGFEAT_INC = UNPACKED / "legfeat_inc.nss"

# Every script this feature adds. NWN resrefs are capped at 16 characters and
# the compiler does not warn — a longer name simply never resolves at runtime.
LEGFEAT_SCRIPTS = [
    "legfeat_db", "legfeat_inc", "legfeat_ids_inc", "legfeat_nui",
    "legfeat_open", "legfeat_evt", "legfeat_lvl", "legfeat_reset",
    "legfeat_respec", "legfeat_cond", "legfeat_equip",
    # The martial replacement set's combat hooks.
    "legfeat_atk_inc", "legfeat_dmg", "legfeat_disarm",
]


def load_generator():
    if not GENERATOR.exists():
        return None
    spec = importlib.util.spec_from_file_location("gen_legendary_feats", GENERATOR)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def read_2da(path):
    """Return (header, {row_index: [cells]}) for a 2DA, ignoring blank rows."""
    text = path.read_text(encoding="latin-1")
    lines = [ln.rstrip("\r\n") for ln in text.splitlines()]
    header = lines[2].split() if len(lines) > 2 else []
    rows = {}
    for ln in lines[3:]:
        cells = ln.split()
        if len(cells) < 2 or not cells[0].isdigit():
            continue
        rows[int(cells[0])] = cells
    return header, rows


def check_table(problems, gen):
    if not FEAT_2DA.exists():
        problems.append(f"{FEAT_2DA} is missing — nothing to pack into the hak")
        return

    header, rows = read_2da(FEAT_2DA)
    if len(header) != gen.BASE_COLUMNS:
        problems.append(
            f"feat.2da has {len(header)} columns, expected {gen.BASE_COLUMNS} — "
            "this looks like the CEP cep2_add_feats copy (44 columns), which "
            "the module does not load")
        return

    base = sorted(i for i in rows if i < gen.FIRST_ROW)
    if len(base) != gen.BASE_ROWS or (base and base[-1] != gen.BASE_ROWS - 1):
        problems.append(
            f"feat.2da has {len(base)} rows below {gen.FIRST_ROW}, expected "
            f"{gen.BASE_ROWS} (stock 0-1115) — the base table is not stock")

    index = {col: pos for pos, col in enumerate(header)}
    refs = gen.strrefs()
    owned = sorted(i for i in rows if i >= gen.FIRST_ROW)
    expected = [gen.FIRST_ROW + n for n in range(len(gen.FEATS))]
    if owned != expected:
        # Bounded: a stray CEP table puts ~23,000 row numbers in this list.
        shown = owned[:8] + (["..."] if len(owned) > 8 else [])
        problems.append(
            f"feat.2da has {len(owned)} row(s) at or above {gen.FIRST_ROW} "
            f"({shown or '(none)'}), generator defines {len(expected)} "
            f"({expected}) — either the table was re-extracted over the "
            "generated rows, or it is not the stock base. Re-run: "
            "python3 bin/gen-legendary-feats.py --apply "
            "[--from-stock /tmp/feat.2da]")
        return

    for row_index, feat in zip(owned, gen.FEATS):
        cells = rows[row_index][1:]

        def cell(col):
            return cells[index[col]] if col in index and index[col] < len(cells) else None

        if cell("LABEL") != feat.label:
            problems.append(
                f"feat.2da row {row_index} is {cell('LABEL')!r}, generator says "
                f"{feat.label!r} — rows renumbered, which turns every granted "
                "feat into a different feat")
        # The load-bearing column: 0 keeps the feat off every class's level-up
        # selection list, leaving the picker as the only grant path.
        if cell("ALLCLASSESCANUSE") != "0":
            problems.append(
                f"feat.2da row {row_index} ({feat.label}) has ALLCLASSESCANUSE="
                f"{cell('ALLCLASSESCANUSE')}, must be 0 — otherwise the engine's "
                "own level-up page can offer it alongside the picker and the "
                "character gets it twice")
        name_ref, desc_ref = refs[feat.label]
        if cell("FEAT") != str(name_ref) or cell("DESCRIPTION") != str(desc_ref):
            problems.append(
                f"feat.2da row {row_index} ({feat.label}) points at strrefs "
                f"{cell('FEAT')}/{cell('DESCRIPTION')}, the TLK block puts its "
                f"strings at {name_ref}/{desc_ref} — stale table, re-run "
                "python3 bin/gen-legendary-feats.py --apply")


def check_not_selectable(problems, gen):
    """No cls_feat_*.2da may list an owned feat id.

    ALLCLASSESCANUSE=0 means "only classes whose feat table lists it", so a
    stray entry in one of those tables would re-open the level-up page path
    that column exists to close.
    """
    owned = {str(gen.FIRST_ROW + n) for n in range(len(gen.FEATS))}
    for path in sorted(HAK_2DA_DIR.glob("cls_feat_*.2da")):
        _, rows = read_2da(path)
        for row_index, cells in rows.items():
            if len(cells) > 1 and cells[1] in owned:
                problems.append(
                    f"{path.name} row {row_index} lists feat {cells[1]}, which "
                    "is a legendary feat — that puts it back on a class's "
                    "level-up page")


def check_packed(problems):
    """feat.2da must be in the hak builder's content list, or it never ships."""
    if not HAK_BUILDER.exists():
        problems.append(f"{HAK_BUILDER} is missing")
        return
    text = HAK_BUILDER.read_text(encoding="utf-8")
    body = text.split("RULES_2DA=(", 1)
    if len(body) < 2 or "feat.2da" not in body[1].split(")", 1)[0]:
        problems.append(
            "bin/build-lotr-rules-hak's RULES_2DA does not list feat.2da — the "
            "legendary rows would never reach a client")


def strip_line_comments(text):
    """Drop // comments so a wiring check cannot match the prose describing it."""
    out = []
    for line in text.splitlines():
        pos = line.find("//")
        out.append(line if pos < 0 else line[:pos])
    return "\n".join(out)


def check_ids_include(problems, gen):
    """unpacked/legfeat_ids_inc.nss must match the generator exactly.

    It is the only place scripts learn a legendary feat's row number. A stale
    copy points the picker at the wrong feat id — it would still grant *a* feat,
    just not the one the player clicked.
    """
    if not IDS_INC.exists():
        problems.append(
            f"{IDS_INC} is missing — run: python3 bin/gen-legendary-feats.py --apply")
        return
    if IDS_INC.read_text(encoding="utf-8") != gen.nss_include():
        problems.append(
            "unpacked/legfeat_ids_inc.nss is stale — it no longer matches the "
            "feat table in bin/gen-legendary-feats.py. Scripts would grant the "
            "wrong feat id. Re-run: python3 bin/gen-legendary-feats.py --apply")


def check_prereqs(problems, gen):
    """Prerequisites must compare with >=, say what they compare, and be shown.

    Roadmap item legendary-feat-prereq-defect-1: a level-60 character with a
    qualifying BAB but no Epic Prowess saw Legendary Prowess greyed out behind
    one flat string, "Requires: BAB 35+, Epic Prowess", and reported it as "35 is
    not accepted". Two separate weaknesses made that report unanswerable, and
    both are gated here:

    1. **The comparison direction was a typing convention.** Nothing stopped a
       `>` being written where `>=` was meant. The generator now emits the
       operator itself, so the only way a `>` can appear is if someone hand-writes
       one back into a clause's `expr` — which is what the first two checks catch.
    2. **The display text and the test were independent strings.** A `>= 35` could
       be advertised as anything at all. They now come from one Req, and the
       threshold check below is what keeps a future refactor from splitting them
       again.

    The last check is the picker side: generating a measured readout that no
    surface displays would leave the player exactly as blind as before.
    """
    if gen is None:
        return
    include = gen.nss_include()

    def body(name):
        """The DEFINITION's body, not the forward declaration's.

        Every one of these functions is declared near the top of the include and
        defined further down, so a plain split on the name finds the prototype
        and returns nothing — which reads as "this feat has no text" for every
        feat at once. Anchor on the `{` that only a definition has.
        """
        match = re.search(rf"^{re.escape(name)}\([^)]*\)\n\{{\n(.*?)\n\}}",
                          include, re.S | re.M)
        return match.group(1) if match else ""

    # 1 + 2. Comparison direction, over the generated test function only. A bare
    #        `>` or any `<` here is a prerequisite that rejects a character who
    #        exactly meets its stated number — the reported defect, literally.
    tests = body("int LegFeat_MeetsPrereq")
    if not tests:
        problems.append(
            "legfeat_ids_inc.nss has no LegFeat_MeetsPrereq body — the "
            "prerequisite gate is not being generated at all")
    for line in tests.splitlines():
        stripped = re.sub(r">=", "", line)
        if ">" in stripped:
            problems.append(
                "a legendary feat prerequisite compares with `>` rather than "
                f"`>=`, so a character on exactly the stated number is refused: "
                f"{line.strip()}")
        if "<" in line:
            problems.append(
                "a legendary feat prerequisite compares with `<`, which inverts "
                f"the clause the picker prints: {line.strip()}")

    # 3. Every threshold in the test must appear in the text for the SAME feat.
    #    "BAB 35+" describing a `>= 30` is worse than no text at all.
    shown = body("string LegFeat_PrereqAt")
    text_by_case = dict(re.findall(r'case (\d+): return "([^"]*)";', shown))
    for case, expr in re.findall(r"case (\d+): return \((.*)\);", tests):
        thresholds = re.findall(r">=\s*(\d+)", expr)
        text = text_by_case.get(case)
        if text is None:
            if thresholds:
                problems.append(
                    f"legendary feat {case} tests a prerequisite but "
                    "LegFeat_PrereqAt has no text for it — the picker would grey "
                    "the row with no reason given")
            continue
        for value in thresholds:
            if not re.search(rf"\b{value}\+", text):
                problems.append(
                    f"legendary feat {case} requires {value} or more but its "
                    f"player-facing text is {text!r} — the number the player is "
                    "told is not the number they are tested against")

    # 4. The measured readout has to reach a surface. Generating it and showing
    #    the old flat string is the defect with extra steps.
    for path, func, what in (
        (UNPACKED / "legfeat_nui.nss", "LegFeat_FirstUnmetAt",
         "the picker's effect column would show no clause and no value"),
        (UNPACKED / "legfeat_evt.nss", "LegFeat_PrereqStatusAt",
         "a refused pick would not say which clause failed"),
    ):
        if not path.exists():
            problems.append(f"{path} is missing")
            continue
        if func not in strip_line_comments(path.read_text(encoding="latin-1")):
            problems.append(
                f"{path.name} does not call {func} — {what} "
                "(roadmap legendary-feat-prereq-defect-1)")

    # 5. ASCII only. The readout reaches the NUI and the chat log, and a
    #    non-ASCII byte in a .nss is a recorded trap in this repo.
    try:
        include.encode("ascii")
    except UnicodeEncodeError as exc:
        problems.append(
            f"legfeat_ids_inc.nss contains a non-ASCII character ({exc.reason} "
            f"at byte {exc.start}) — keep generated NWScript to plain ASCII")


def check_wiring(problems):
    """The three hooks without which the feature is silently inert or lossy."""
    for name in LEGFEAT_SCRIPTS:
        if len(name) > 16:
            problems.append(
                f"script resref {name!r} is {len(name)} characters — NWN caps "
                "resrefs at 16 and the compiler does not warn; it simply never "
                "resolves at runtime")
        if not (UNPACKED / f"{name}.nss").exists():
            problems.append(f"unpacked/{name}.nss is missing")

    # 1. The level-60 trigger. Without it nothing ever opens the picker.
    if MODULE_LOAD.exists():
        text = strip_line_comments(MODULE_LOAD.read_text(encoding="latin-1"))
        if "legfeat_lvl" not in text:
            problems.append(
                "onmoduleload.nss does not subscribe legfeat_lvl to "
                "NWNX_ON_LEVEL_UP_AFTER — reaching level 60 would never open "
                "the picker")

    # 2. The login re-apply. THE failure this design is most likely to ship: the
    #    feat persists in the .bic, its effects do not, and a missing re-apply
    #    has no symptom beyond a bonus quietly absent from the character sheet.
    if CLIENT_ENTER.exists():
        # Comments stripped first: this file explains the call right above it,
        # and a substring search would happily match the explanation after
        # someone deleted the call.
        text = strip_line_comments(CLIENT_ENTER.read_text(encoding="latin-1"))
        if "LegFeat_ApplyAll" not in text:
            problems.append(
                "mod_cliententer.nss does not call LegFeat_ApplyAll — every "
                "legendary feat's effect would be lost on logout and never come "
                "back, with no error and no message")

    # 3. The rest recovery path for a dismissed or half-finished picker. Also
    #    the only route by which a character who reached 60 before this feature
    #    existed ever gets its picks.
    for path in REST_HOOKS:
        if not path.exists():
            problems.append(f"unpacked/{path.name} is missing")
            continue
        text = strip_line_comments(path.read_text(encoding="latin-1"))
        if "legfeat_open" not in text:
            problems.append(
                f"{path.name} does not open the picker — Force Rest is the only "
                "rest that completes in this module (the engine's rest is "
                "cancelled at REST_STARTED to open the rest menu), so a player "
                "who dismisses the window, or who was already level 60 when "
                "this shipped, would have no way to spend their picks")

    # 4. The admin reset tool must stay reachable. It is the only in-game way to
    #    put a test character back to "never had a legendary feat", and a feat
    #    granted by NWNX lives in the .bic where nothing else will remove it.
    if REST_DLG.exists():
        dlg = json.loads(REST_DLG.read_text(encoding="utf-8"))
        scripts = {
            (r.get("Script", {}) or {}).get("value", "")
            for r in dlg.get("ReplyList", {}).get("value", [])
        }
        if "legfeat_reset" not in scripts:
            problems.append(
                "emotewand.dlg.json has no reply running legfeat_reset — the "
                "Admin Options reset tool is unreachable, and a legendary feat "
                "in a .bic cannot be removed any other way in game")

    # 5. The player-facing re-pick must stay reachable, and must give the base
    #    ability points back with the feat. A re-pick that removes the feat but
    #    keeps the +6 is a stat farm: swap feats repeatedly, bank the bonus each
    #    time. LegFeat_RevokeAll is the one path that undoes both, so the
    #    respec has to go through it rather than growing its own removal loop.
    if RESPEC_DLG.exists():
        dlg = json.loads(RESPEC_DLG.read_text(encoding="utf-8"))
        scripts = {
            (r.get("Script", {}) or {}).get("value", "")
            for r in dlg.get("ReplyList", {}).get("value", [])
        }
        if "legfeat_respec" not in scripts:
            problems.append(
                "_pc_builder_v1.dlg.json has no reply running legfeat_respec — "
                "players would have no way to re-choose their legendary feats")
    if LEGFEAT_INC.exists():
        text = strip_line_comments(LEGFEAT_INC.read_text(encoding="latin-1"))
        body = text.split("int LegFeat_Respec", 1)
        if len(body) < 2 or "LegFeat_RevokeAll" not in body[1]:
            problems.append(
                "legfeat_inc.nss LegFeat_Respec does not call LegFeat_RevokeAll "
                "— a re-pick that hands back the feat but keeps the base ability "
                "points is a stat farm, repeatable as often as the player likes")

    # 6. Base-score feats must never be re-applied at login. The bonus is
    #    written into the .bic, so a second application is permanent, silent and
    #    cumulative: +6 per session, forever.
    if LEGFEAT_INC.exists():
        text = strip_line_comments(LEGFEAT_INC.read_text(encoding="latin-1"))
        body = text.split("void LegFeat_ApplyAll", 1)
        if len(body) < 2 or "LEGFEAT_KIND_RAW" not in body[1]:
            problems.append(
                "legfeat_inc.nss LegFeat_ApplyAll does not skip "
                "LEGFEAT_KIND_RAW feats — base ability scores live in the .bic, "
                "so re-applying at login stacks another bonus every session")
        # HOOK feats have no effect to rebuild; ApplyAll must skip them too, or
        # it drops into LegFeat_ApplyOne looking for a case that must not exist.
        elif "LEGFEAT_KIND_HOOK" not in body[1]:
            problems.append(
                "legfeat_inc.nss LegFeat_ApplyAll does not skip "
                "LEGFEAT_KIND_HOOK feats — a hook feat grants nothing by design "
                "and must never be routed through LegFeat_ApplyOne")


    # 6b. Conditional feats need the equip hook. Legendary Onslaught's extra
    #     attack is melee-only, so it has to be rebuilt when the character
    #     changes weapons. Without the subscription the effect goes stale in the
    #     player's favour and in silence: swap a sword for a bow and you keep a
    #     melee-only bonus attack until your next login.
    if MODULE_LOAD.exists():
        text = strip_line_comments(MODULE_LOAD.read_text(encoding="latin-1"))
        if "legfeat_equip" not in text:
            problems.append(
                "onmoduleload.nss does not subscribe legfeat_equip to the item "
                "equip/unequip events — conditional legendary feats (melee-only "
                "extra attacks) would keep applying after the weapon they depend "
                "on is put away")

    # 7. Prerequisites must bind on the server, not just in the window. The
    #    picker greys an unqualified row, but the window is a client-side
    #    snapshot — a player holding a stale one (took the prerequisite feat's
    #    rival, or lost a prerequisite to a relevel) would otherwise buy straight
    #    past the check. LegFeat_Take is where the decision actually has to live.
    if LEGFEAT_INC.exists():
        text = strip_line_comments(LEGFEAT_INC.read_text(encoding="latin-1"))
        body = text.split("int LegFeat_Take", 1)
        if len(body) < 2 or "LegFeat_MeetsPrereq" not in body[1]:
            problems.append(
                "legfeat_inc.nss LegFeat_Take does not call LegFeat_MeetsPrereq "
                "— prerequisites would be enforced only by the picker's greyed "
                "buttons, which is to say only by the client")


def check_stock_overrides(problems, gen, rows, header):
    """Stock rows we repointed must still point at our TLK.

    Devastating Critical's shipped description says the target must save or die.
    That has not been true since the devcrit-roll rework, so all 40 weapon rows
    were repointed at a string in our own block. The failure mode this catches
    is specific and silent: re-extracting feat.2da from the game data (or a
    --from-stock reseed that skipped the generator) restores Bioware's strref,
    and the only symptom is a feat in the character sheet describing a rule the
    module no longer has.
    """
    try:
        overrides = gen.stock_overrides()
    except Exception as exc:                      # pragma: no cover
        problems.append(f"cannot compute stock overrides: {exc}")
        return
    for row, changes in sorted(overrides.items()):
        cells = rows.get(row)
        if cells is None:
            problems.append(f"feat.2da is missing stock row {row}")
            continue
        for column, want in changes.items():
            got = cells[1 + header.index(column)]
            if got != want:
                problems.append(
                    f"feat.2da row {row} ({cells[1]}) has {column}={got}, "
                    f"expected {want} — the stock description was restored, so "
                    "the feat now describes a rule the module does not have. "
                    "Re-run bin/gen-legendary-feats.py --apply")
                return          # 40 identical rows; one message is enough


def check_effect_payloads(problems, gen):
    """Every EFFECT-kind feat must actually do something.

    An ability feat is table-driven (ability + bonus come from the generator),
    but any other EFFECT feat needs a hand-written case in LegFeat_ApplyOne.
    Without one it fails in the worst possible way: the pick is spent, the feat
    appears on the character sheet with its real name and description, and the
    benefit simply never arrives — no error, nothing in the log.

    A HOOK feat is the deliberate opposite: it grants nothing here, because
    something else reads it with GetHasFeat. That has exactly the same silent
    failure mode if the reader does not exist, so it gets the mirror-image
    check — somewhere under unpacked/ must actually test for it.
    """
    if not LEGFEAT_INC.exists():
        return
    text = strip_line_comments(LEGFEAT_INC.read_text(encoding="latin-1"))
    body = text.split("void LegFeat_ApplyOne", 1)
    if len(body) < 2:
        problems.append("legfeat_inc.nss has no LegFeat_ApplyOne")
        return
    apply_one = body[1].split("\nvoid LegFeat_ApplyAll", 1)[0]

    for feat in gen.FEATS:
        if feat.kind == "hook":
            const = f"FEAT_{feat.label}"
            readers = [
                path.name for path in UNPACKED.glob("*.nss")
                if path.name != "legfeat_ids_inc.nss"
                and re.search(rf"GetHasFeat\(\s*{const}\b",
                              path.read_text(encoding="latin-1"))
            ]
            if not readers:
                problems.append(
                    f"{const} is a HOOK-kind feat, so it grants nothing itself "
                    "and relies on a combat hook reading it — but no script "
                    f"under unpacked/ calls GetHasFeat({const}). The pick would "
                    "be spent and nothing would ever happen")
            continue
        if feat.kind == "raw_ability" or feat.ability >= 0:
            continue
        if f"FEAT_{feat.label}" not in apply_one:
            problems.append(
                f"FEAT_{feat.label} is an EFFECT-kind feat with no ability "
                "payload and no case in legfeat_inc.nss LegFeat_ApplyOne — the "
                "pick would be spent and nothing at all would happen")


def check_hook_arming(problems, gen):
    """Every hook feat whose reader has to be switched on must be in ArmHooks.

    The hook feats do not all work the same way. Legendary Butcher is read by
    devcrit_atk.nss, which is registered server-wide and runs for everybody, so
    it needs no arming. The rest are deliberately NOT server-wide, because they
    would otherwise put work on every attack and every point of damage on the
    server:

      * legfeat_atk_inc.nss runs only behind a LEGFEAT_ATK_VAR local int
      * legfeat_dmg.nss is registered per character, on nobody else

    Both are switched on by LegFeat_ArmHooks. A feat read by one of those two
    files and missing from ArmHooks has the same silent failure as a feat with
    no reader at all — the reader exists, and is never reached.
    """
    if not LEGFEAT_INC.exists():
        return
    text = strip_line_comments(LEGFEAT_INC.read_text(encoding="latin-1"))
    body = text.split("void LegFeat_ArmHooks", 1)
    if len(body) < 2:
        problems.append(
            "legfeat_inc.nss has no LegFeat_ArmHooks — the gated hook feats "
            "(legfeat_atk_inc / legfeat_dmg) would never be switched on")
        return
    arm_hooks = body[1].split("\n}", 1)[0]

    gated = ("legfeat_atk_inc.nss", "legfeat_dmg.nss")
    for feat in gen.FEATS:
        if feat.kind != "hook":
            continue
        const = f"FEAT_{feat.label}"
        read_by_gated = any(
            re.search(rf"GetHasFeat\(\s*{const}\b",
                      (UNPACKED / name).read_text(encoding="latin-1"))
            for name in gated if (UNPACKED / name).exists())
        if read_by_gated and const not in arm_hooks:
            problems.append(
                f"{const} is read by a GATED hook (legfeat_atk_inc or "
                "legfeat_dmg) but is not named in LegFeat_ArmHooks, so the "
                "hook is never switched on for a character who takes it — the "
                "pick is spent and nothing happens")


def main():
    problems = []
    gen = load_generator()
    if gen is None:
        problems.append(
            f"{GENERATOR} is missing — nothing owns the legendary feat rows")
    else:
        check_table(problems, gen)
        if FEAT_2DA.exists():
            header, rows = read_2da(FEAT_2DA)
            check_stock_overrides(problems, gen, rows, header)
        check_not_selectable(problems, gen)
        check_ids_include(problems, gen)
        check_prereqs(problems, gen)
        check_effect_payloads(problems, gen)
        check_hook_arming(problems, gen)
    check_packed(problems)
    check_wiring(problems)

    if problems:
        print("FAIL: legendary feat table has drifted\n", file=sys.stderr)
        for p in problems:
            print(f"  - {p}", file=sys.stderr)
        return 1
    count = len(gen.FEATS) if gen else 0
    overridden = len(gen.stock_overrides()) if gen else 0
    print(f"ok: legendary feats coherent ({count} rows from "
          f"{gen.FIRST_ROW}, stock base intact, {overridden} stock row(s) "
          "repointed, none selectable at level-up, picker wired)")
    return 0


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""Store blueprint/placement divergence check (build-time smoke test).

A `.utm` store blueprint is NOT what the player shops from. The placed store
instance inside `<area>.git.json` carries its own copy of the whole inventory --
and where the blueprint lists a resref (`InventoryRes` + `Infinite`), the
instance embeds the entire item (`TemplateResRef`, `Cost`, `StackSize`,
`Infinite`, `Repos_Pos*`, properties). The engine reads the instance. The
blueprint is only consulted when a store is created fresh from it.

So editing a `.utm` and repacking changes nothing in game, silently. That is the
trap this gate exists to catch: stock added to `wellshop.utm.json` and
`methmart.utm.json` never appeared in the Well-Mart or Meth-Mart, because the
real inventory lives in `thewelloferu.git.json` and `area042.git.json`
(commit 25c60a20d30).

Unlike creatures there is no respawn path here, so divergence is not a runtime
correctness bug -- it is a maintenance one: it makes the blueprint a lie. The
rule is therefore the same in spirit as tests/check_divergent_creatures.py:

    LOCAL blueprint (a <resref>.utm.json exists) placed in an area:
        the placement's inventory and its trading fields must match the
        blueprint's, so an edit to either side means what it says.
    STOCK blueprint (nw_store*, x2_store*, ... - no local .utm):
        not checked. There is no local file to edit and no baseline to read, and
        two shops legitimately sharing a stock resref with different stock is
        normal (nw_storgenral001 is placed in five areas).

Stack sizes: a blueprint entry has no stack size of its own -- it instantiates
the item blueprint, so its stack is that `.uti`'s `StackSize`. For a stock item
(no local `.uti`) the stack is unknowable and is not compared.

Known divergences live in tests/known_store_divergence.json, keyed
"<store>@<area>", each with a reason. That file is a burn-down list, not a
parking space: it exists so the gate can land on a tree that already diverges,
and every entry left in it is a blueprint that does not describe its shop.

Scans unpacked/ directly (module-index/ is gitignored and may be absent on a
fresh clone). Exits 0 if every locally-blueprinted store matches its placements,
1 otherwise.
"""

import glob
import json
import os
import sys
from collections import Counter, defaultdict

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
UNPACKED = os.path.join(ROOT, "unpacked")
KNOWN_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                          "known_store_divergence.json")
STOCK_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                          "stock_item_stacks.json")

# Trading fields the instance overrides independently of the item list. A
# MaxBuyPrice or MarkUp that differs between blueprint and placement is the same
# class of lie as a missing item -- Methonash's Well-Mart exists specifically to
# have a 100k buy cap.
FIELDS = ("BlackMarket", "BM_MarkDown", "IdentifyPrice", "MarkDown", "MarkUp",
          "MaxBuyPrice", "StoreGold", "OnOpenStore", "OnStoreClosed")


def fld(struct, key):
    v = struct.get(key) if isinstance(struct, dict) else None
    return v.get("value") if isinstance(v, dict) else None


def sub_list(struct, key):
    v = struct.get(key)
    if isinstance(v, dict):
        v = v.get("value")
    return v if isinstance(v, list) else []


_UTI_STACK = {}
_STOCK_STACKS = None


def stock_stacks():
    """Stock resref -> StackSize for the items that don't ship at 1.

    Committed table, built by bin/gen-stock-item-stacks.py from the install's
    BIF archives, so the gate never needs a local NWN install. Assuming 1 here
    was wrong and produced 21 false divergences: stock ammunition ships at 99
    and throwing weapons at 50, which is exactly what the placements sell.
    """
    global _STOCK_STACKS
    if _STOCK_STACKS is None:
        try:
            with open(STOCK_PATH, encoding="utf-8") as fh:
                _STOCK_STACKS = json.load(fh).get("stacks", {})
        except (OSError, json.JSONDecodeError):
            _STOCK_STACKS = {}
    return _STOCK_STACKS


def item_stack(resref):
    """The stack a blueprint store entry would hand out for this resref.

    A `.utm` entry is a resref, not an item, so its stack size is whatever the
    item blueprint says: the local `.uti` when we have one, else the stock table
    above, else 1. A placement selling a resref at a stack its blueprint would
    not hand out is a real divergence -- the module's convention for bulk is a
    separate pack blueprint carrying the stack (`it_mpotion029` 1x /
    `it_mpotion032` 10x), not an instance-level override.
    """
    if resref not in _UTI_STACK:
        p = os.path.join(UNPACKED, f"{resref}.uti.json")
        if os.path.exists(p):
            _UTI_STACK[resref] = fld(json.load(open(p, encoding="utf-8")), "StackSize")
        else:
            _UTI_STACK[resref] = stock_stacks().get(resref, 1)
    return _UTI_STACK[resref] or 1


def pages(store, embedded):
    """{page id: {resref: Counter((stack, infinite))}}.

    `embedded` picks the placement shape (full item structs) over the blueprint
    shape (resref + Infinite only).
    """
    out = {}
    for page in sub_list(store, "StoreList"):
        pid = page.get("__struct_id")
        entries = defaultdict(Counter)
        for it in sub_list(page, "ItemList"):
            if embedded:
                resref = fld(it, "TemplateResRef")
                stack = fld(it, "StackSize") or 1
            else:
                resref = fld(it, "InventoryRes")
                stack = item_stack(resref)      # None => unknowable, not compared
            if not resref:
                continue
            entries[resref][(stack, int(fld(it, "Infinite") or 0))] += 1
        out[pid] = entries
    return out


def compare_page(bp_entries, inst_entries):
    """Differences on one store page, as a list of human-readable strings."""
    diffs = []
    for resref in sorted(set(bp_entries) | set(inst_entries)):
        bp = bp_entries.get(resref, Counter())
        inst = inst_entries.get(resref, Counter())
        n_bp, n_inst = sum(bp.values()), sum(inst.values())
        if n_bp and not n_inst:
            diffs.append(f"blueprint sells {resref} (x{n_bp}), the placement does not")
            continue
        if n_inst and not n_bp:
            diffs.append(f"placement sells {resref} (x{n_inst}), the blueprint does not")
            continue
        if n_bp != n_inst:
            diffs.append(f"{resref}: blueprint x{n_bp}, placement x{n_inst}")
            continue
        bp_inf = sorted(inf for (_s, inf), n in bp.items() for _ in range(n))
        inst_inf = sorted(inf for (_s, inf), n in inst.items() for _ in range(n))
        if bp_inf != inst_inf:
            diffs.append(f"{resref}: Infinite blueprint={bp_inf} placement={inst_inf}")
        bp_stk = sorted(s for (s, _i), n in bp.items() for _ in range(n))
        inst_stk = sorted(s for (s, _i), n in inst.items() for _ in range(n))
        if bp_stk != inst_stk:
            diffs.append(f"{resref}: StackSize blueprint={bp_stk} placement={inst_stk}")
    return diffs


def load_known():
    if not os.path.exists(KNOWN_PATH):
        return {}
    with open(KNOWN_PATH, encoding="utf-8") as fh:
        data = json.load(fh)
    return data.get("known", data) if isinstance(data, dict) else {}


def main():
    known = load_known()
    local = {os.path.basename(p)[:-len(".utm.json")]
             for p in glob.glob(os.path.join(UNPACKED, "*.utm.json"))}

    placed = defaultdict(list)      # store resref -> [area, ...]
    failures = []                   # (key, [diff, ...])
    checked = 0

    for gf in sorted(glob.glob(os.path.join(UNPACKED, "*.git.json"))):
        area = os.path.basename(gf)[:-len(".git.json")]
        try:
            d = json.load(open(gf, encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as e:
            print(f"[divergent-stores] FAIL: unreadable {area}.git.json: {e}", file=sys.stderr)
            return 1
        for s in sub_list(d, "StoreList"):
            resref = fld(s, "ResRef")
            if not resref:
                continue
            placed[resref].append(area)
            if resref not in local:
                continue                     # stock blueprint: nothing to compare
            checked += 1
            bp = json.load(open(os.path.join(UNPACKED, f"{resref}.utm.json"),
                                encoding="utf-8"))
            diffs = []
            for f in FIELDS:
                if fld(bp, f) != fld(s, f):
                    diffs.append(f"field {f}: blueprint={fld(bp, f)!r} "
                                 f"placement={fld(s, f)!r}")
            bp_pages, inst_pages = pages(bp, False), pages(s, True)
            for pid in sorted(set(bp_pages) | set(inst_pages), key=lambda x: (x is None, x)):
                for diff in compare_page(bp_pages.get(pid, {}), inst_pages.get(pid, {})):
                    diffs.append(f"page {pid}: {diff}")
            if diffs:
                failures.append((f"{resref}@{area}", diffs))

    unknown = [(k, diffs) for k, diffs in failures if k not in known]

    # Advisory only: a local blueprint nobody placed is unreachable in the same
    # way, but it may be waiting to be placed, so it never fails the build.
    orphans = sorted(local - set(placed))

    if unknown:
        print(f"[divergent-stores] FAIL: {len(unknown)} placed store(s) do not match "
              "their blueprint. The PLACEMENT is what the player shops from, so an "
              "edit to the .utm alone changes nothing in game:", file=sys.stderr)
        for key, diffs in unknown:
            print(f"  - {key}  ({len(diffs)} difference(s))", file=sys.stderr)
            for diff in diffs[:12]:
                print(f"      {diff}", file=sys.stderr)
            if len(diffs) > 12:
                print(f"      ... and {len(diffs) - 12} more", file=sys.stderr)
        print("\nFix: make the two sides agree — usually by syncing the blueprint "
              "FROM the placement (the placement is live stock; rewriting it from "
              "the blueprint changes what players can buy). Add an entry to "
              "tests/known_store_divergence.json only to burn a case down later, "
              "with a reason.", file=sys.stderr)
        return 1

    print(f"[divergent-stores] OK: {checked} placement(s) of {len(local & set(placed))} "
          f"local store blueprint(s) match" + (f"; {len(known)} known divergence(s)"
                                              if known else "")
          + (f"; {len(orphans)} local blueprint(s) placed nowhere" if orphans else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main())

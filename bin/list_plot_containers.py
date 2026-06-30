#!/usr/bin/env python3
"""List all locked plot containers without a key requirement across the module."""

import argparse
import glob
import json
import os
import sys

UNPACKED = os.path.join(os.path.dirname(__file__), "..", "unpacked")


def v(node, default=""):
    return node.get("value", default) if isinstance(node, dict) else default


def get_area_names():
    names = {}
    for path in glob.glob(os.path.join(UNPACKED, "*.are.json")):
        resref = os.path.basename(path).replace(".are.json", "")
        with open(path) as f:
            data = json.load(f)
        name = v(data.get("Name", {}).get("value", {}), {})
        if isinstance(name, dict):
            names[resref] = name.get("0", resref)
        else:
            names[resref] = resref
    return names


def collect_plot_containers(area_names):
    results = []
    for path in sorted(glob.glob(os.path.join(UNPACKED, "*.git.json"))):
        resref = os.path.basename(path).replace(".git.json", "")
        with open(path) as f:
            data = json.load(f)
        placeables = data.get("Placeable List", {}).get("value", [])
        for p in placeables:
            if not isinstance(p, dict):
                continue
            plot = v(p.get("Plot", {}), 0)
            has_inv = v(p.get("HasInventory", {}), 0)
            locked = v(p.get("Locked", {}), 0)
            key_req = v(p.get("KeyRequired", {}), 0)
            key_name = v(p.get("KeyName", {}), "")
            if plot != 1 or has_inv != 1 or locked != 1 or key_req != 0 or key_name != "":
                continue

            loc_name_raw = p.get("LocName", {}).get("value", {})
            if isinstance(loc_name_raw, dict):
                name = loc_name_raw.get("0", "")
            else:
                name = ""
            tag = v(p.get("Tag", {}), "")
            if not name:
                name = tag

            open_dc = v(p.get("OpenLockDC", {}), 0)

            results.append({
                "name": name,
                "tag": tag,
                "area_resref": resref,
                "area_name": area_names.get(resref, resref),
                "open_dc": open_dc,
            })
    return results


def print_table(rows):
    if not rows:
        print("No locked plot containers without a key found.")
        return
    cols = ["name", "tag", "area_name", "open_dc"]
    headers = ["Container Name", "Tag", "Area", "Unlock DC"]
    widths = [max(len(h), max((len(str(r[c])) for r in rows), default=0)) for h, c in zip(headers, cols)]
    sep = "  "
    header_line = sep.join(h.ljust(w) for h, w in zip(headers, widths))
    print(header_line)
    print("-" * len(header_line))
    for row in rows:
        print(sep.join(str(row[c]).ljust(w) for c, w in zip(cols, widths)))
    print(f"\n{len(rows)} locked plot container(s) without a key.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--json", action="store_true", help="Output as JSON array")
    args = parser.parse_args()

    area_names = get_area_names()
    rows = collect_plot_containers(area_names)

    if args.json:
        json.dump(rows, sys.stdout, indent=2)
        print()
    else:
        print_table(rows)


if __name__ == "__main__":
    main()

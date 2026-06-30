#!/usr/bin/env python3
"""List all locked plot doors without a key requirement across the module."""

import argparse
import glob
import json
import os
import sys

UNPACKED = os.path.join(os.path.dirname(__file__), "..", "unpacked")

DEST_TYPES = {0: "none/trigger", 1: "door", 2: "waypoint"}


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


def collect_plot_doors(area_names):
    results = []
    for path in sorted(glob.glob(os.path.join(UNPACKED, "*.git.json"))):
        resref = os.path.basename(path).replace(".git.json", "")
        with open(path) as f:
            data = json.load(f)
        doors = data.get("Door List", {}).get("value", [])
        for door in doors:
            if not isinstance(door, dict):
                continue
            plot = v(door.get("Plot", {}), 0)
            locked = v(door.get("Locked", {}), 0)
            key_req = v(door.get("KeyRequired", {}), 0)
            key_name = v(door.get("KeyName", {}), "")
            if plot != 1 or locked != 1 or key_req != 0 or key_name != "":
                continue

            loc_name_raw = door.get("LocName", {}).get("value", {})
            if isinstance(loc_name_raw, dict):
                door_name = loc_name_raw.get("0", "")
            else:
                door_name = ""
            tag = v(door.get("Tag", {}), "")
            if not door_name:
                door_name = tag

            linked_to = v(door.get("LinkedTo", {}), "")
            linked_flags = v(door.get("LinkedToFlags", {}), 0)
            dest_type = DEST_TYPES.get(linked_flags, f"unknown({linked_flags})")
            open_dc = v(door.get("OpenLockDC", {}), 0)

            results.append({
                "door_name": door_name,
                "door_tag": tag,
                "area_resref": resref,
                "area_name": area_names.get(resref, resref),
                "dest_tag": linked_to,
                "dest_type": dest_type,
                "open_dc": open_dc,
            })
    return results


def print_table(rows):
    if not rows:
        print("No plot doors without a key found.")
        return
    cols = ["door_name", "door_tag", "area_name", "dest_tag", "dest_type", "open_dc"]
    headers = ["Door Name", "Door Tag", "Area", "Dest Tag", "Dest Type", "Unlock DC"]
    widths = [max(len(h), max((len(str(r[c])) for r in rows), default=0)) for h, c in zip(headers, cols)]
    sep = "  "
    header_line = sep.join(h.ljust(w) for h, w in zip(headers, widths))
    print(header_line)
    print("-" * len(header_line))
    for row in rows:
        print(sep.join(str(row[c]).ljust(w) for c, w in zip(cols, widths)))
    print(f"\n{len(rows)} locked plot door(s) without a key.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--json", action="store_true", help="Output as JSON array")
    args = parser.parse_args()

    area_names = get_area_names()
    rows = collect_plot_doors(area_names)

    if args.json:
        json.dump(rows, sys.stdout, indent=2)
        print()
    else:
        print_table(rows)


if __name__ == "__main__":
    main()

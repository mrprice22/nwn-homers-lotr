#!/usr/bin/env python3
"""season-appfolder.py — put THIS season's app-grid shortcuts in their own folder.

`bin/season-shortcuts.sh` writes the .desktop files; this puts them in a GNOME
app-grid folder so each season is one tile instead of eleven loose icons. It is
called from that script and is not normally run by hand.

WHY THIS EXISTS. Two seasons' shortcut sets look near-identical -- same eleven
icons, same labels apart from a trailing realm tag -- and the buttons include
"Shut Down Server". On 2026-08-13 the TEST realm's set was left unfoldered next
to Season 2's folder and the wrong "Shut Down" was clicked: the dev realm went
down and live Season 2 kept running. Foldering is not cosmetic here; it is what
keeps the live server's stop button away from the test one.

TWO SETTINGS, BOTH OF WHICH MATTER. This is the trap that made the first manual
fix look like it had not worked:

  org.gnome.desktop.app-folders   folder-children + each folder's `apps` --
                                  WHICH folder an app belongs to.
  org.gnome.shell                 app-picker-layout -- a cache pinning icons to
                                  grid positions. An app still pinned here is
                                  drawn at the TOP LEVEL even though it is in a
                                  folder, and a brand-new folder id that is
                                  absent here lands wherever the shell decides.

So this touches both: it adds/updates the folder, and strips this season's app
ids out of the cached layout while making sure the folder id is in it.

FOREIGN ENTRIES ARE PRESERVED. Season 1's folder also holds the Steam game
client, which no season owns. Rewriting `apps` to just this season's set would
evict it to the base grid -- the exact thing we are trying to avoid -- so
anything already in the folder that this season does not own is kept, in order,
ahead of our own entries.

ADOPTION, NOT DUPLICATION. Folder ids in the wild are inconsistent (season 1 is
the legacy `NWN`, season 2 is a UUID from the GNOME UI, dev is `nwn-test`). So
rather than insisting on its own id, this first looks for an existing folder that
already contains any of our app ids and reuses it. Only if none exists does it
create the canonical `--id`.

USAGE
    season-appfolder.py --id nwn-s2 --name "Season 2 NWN" --apps a.desktop b...
    season-appfolder.py ... --apply     # write
    season-appfolder.py ... --remove    # take our apps back out of the folder

Dry run by default: prints what would change and exits 0.

Exit 0 even when GNOME/gsettings is unavailable (a headless season host has no
app grid) -- a missing app folder must never fail a shortcut install.
"""
import argparse
import sys

SCHEMA_FOLDERS = "org.gnome.desktop.app-folders"
SCHEMA_FOLDER = "org.gnome.desktop.app-folders.folder"
FOLDER_PATH = "/org/gnome/desktop/app-folders/folders/%s/"
SCHEMA_SHELL = "org.gnome.shell"
KEY_LAYOUT = "app-picker-layout"


def load_gi():
    """Import Gio/GLib, or return None if this box has no GNOME settings."""
    try:
        import gi
        gi.require_version("Gio", "2.0")
        from gi.repository import Gio, GLib
    except (ImportError, ValueError):
        return None
    source = Gio.SettingsSchemaSource.get_default()
    if source is None or source.lookup(SCHEMA_FOLDERS, True) is None:
        return None
    return Gio, GLib


def folder_settings(Gio, folder_id):
    return Gio.Settings.new_with_path(SCHEMA_FOLDER, FOLDER_PATH % folder_id)


def find_owning_folder(Gio, children, ours):
    """The existing folder that already holds any of our apps, if there is one."""
    for fid in children:
        apps = list(folder_settings(Gio, fid).get_strv("apps"))
        if any(a in ours for a in apps):
            return fid
    return None


def read_layout(Gio, GLib):
    """app-picker-layout as [[app_id, ...], ...], one list per page, in order.

    unpack() rather than walking the variant by hand: the value type is
    aa{sv} where each value is a `v` wrapping another a{sv}, and stepping through
    that with get_child_value() lands on the inner dict rather than a dict entry
    -- which still yields the right positions but spews a GLib type assertion on
    every key. unpack() gives plain dicts and no warnings.
    """
    shell = Gio.Settings.new(SCHEMA_SHELL)
    pages = []
    for page in shell.get_value(KEY_LAYOUT).unpack():
        items = sorted(
            (meta.get("position", 0), key) for key, meta in page.items()
        )
        pages.append([key for _, key in items])
    return shell, pages


def write_layout(Gio, GLib, shell, pages):
    """Rebuild the aa{sv} layout, renumbering positions contiguously per page."""
    builder = GLib.VariantBuilder(GLib.VariantType("aa{sv}"))
    for page in pages:
        page_builder = GLib.VariantBuilder(GLib.VariantType("a{sv}"))
        for position, key in enumerate(page):
            inner = GLib.Variant("a{sv}", {"position": GLib.Variant("i", position)})
            page_builder.add_value(
                GLib.Variant("{sv}", (key, GLib.Variant("v", inner)))
            )
        builder.add_value(page_builder.end())
    shell.set_value(KEY_LAYOUT, builder.end())
    Gio.Settings.sync()


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--id", required=True, help="canonical folder id if none exists")
    ap.add_argument("--name", required=True, help="folder name shown in the grid")
    ap.add_argument("--apps", nargs="+", required=True, metavar="DESKTOP",
                    help="this season's .desktop ids, in the order to show them")
    mode = ap.add_mutually_exclusive_group()
    mode.add_argument("--apply", action="store_true", help="write the changes")
    mode.add_argument("--remove", action="store_true",
                      help="take our apps out of the folder (drop it if empty)")
    args = ap.parse_args()

    gi_mods = load_gi()
    if gi_mods is None:
        print("app-folder: no GNOME settings on this host — skipping "
              "(shortcuts themselves are unaffected)")
        return 0
    Gio, GLib = gi_mods

    ours = list(dict.fromkeys(args.apps))          # de-dupe, keep order
    ours_set = set(ours)

    folders = Gio.Settings.new(SCHEMA_FOLDERS)
    children = list(folders.get_strv("folder-children"))

    folder_id = find_owning_folder(Gio, children, ours_set) or args.id
    adopted = folder_id != args.id
    settings = folder_settings(Gio, folder_id)
    existing = list(settings.get_strv("apps"))

    # Entries in the folder that no season owns (e.g. the Steam game client)
    # stay put, ahead of ours, so nothing is evicted to the base grid.
    foreign = [a for a in existing if a not in ours_set]

    if args.remove:
        want_apps = foreign
        want_children = children if want_apps else [c for c in children
                                                    if c != folder_id]
    else:
        want_apps = foreign + ours
        want_children = children if folder_id in children else children + [folder_id]

    print("app-folder      : %s (id %s%s)"
          % (args.name, folder_id, ", adopted existing" if adopted else ""))
    if foreign:
        print("  kept (not ours): %s" % ", ".join(foreign))
    stale = [a for a in existing if a in ours_set and a not in want_apps]
    if stale:
        print("  removed        : %s" % ", ".join(stale))
    added = [a for a in want_apps if a not in existing]
    if added:
        print("  added          : %s" % ", ".join(added))
    if not (stale or added) and want_children == children:
        print("  already correct")

    # The cached layout, rebuilt as we want it, then compared. Declarative on
    # purpose: the first cut keyed the rewrite off "are any of our apps pinned",
    # which silently skipped --remove (nothing of ours is pinned once it is in a
    # folder) and left the retired season's folder id behind as a ghost tile.
    shell, pages = read_layout(Gio, GLib)
    pinned = [a for page in pages for a in page if a in ours_set]

    want_pages = [[a for a in page if a not in ours_set and a != folder_id]
                  for page in pages]
    if not args.remove:
        if not want_pages:
            want_pages = [[]]
        want_pages[0].append(folder_id)
    want_pages = [p for p in want_pages if p]

    if pinned:
        print("  unpinning from the shell's cached grid layout: %s"
              % ", ".join(pinned))
    if want_pages != pages:
        print("  updating the shell's cached grid layout (folder %s)"
              % ("removed" if args.remove else "placed"))

    # --remove always writes; only the bare form is a preview.
    if not args.apply and not args.remove:
        print("DRY RUN — re-run with --apply to write.")
        return 0

    settings.set_string("name", args.name)
    settings.set_boolean("translate", False)
    settings.set_strv("apps", want_apps)
    folders.set_strv("folder-children", want_children)

    if want_pages != pages:
        write_layout(Gio, GLib, shell, want_pages)

    Gio.Settings.sync()
    print("  done — log out and back in for the app grid to redraw.")
    return 0


if __name__ == "__main__":
    sys.exit(main())

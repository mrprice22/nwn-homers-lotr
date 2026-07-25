#!/usr/bin/env bash
# Install / remove THIS season's app-grid shortcuts — both the ops set (restart,
# stop, monitor, logs) and the dev set (unpack, repack x3, wiki, nwsync x2).
#
#   OPS shortcuts   restart / stop / monitor / logs — PER SEASON, because during
#                   a cutover overlap two servers are running and each needs its
#                   own. Each Exec points at its own repo's bin/, so the season
#                   is implied by the path and they take no arguments.
#
#   DEV shortcuts   unpack / repack / repack-clean / repack-test / wiki /
#                   refresh-nwsync — ALSO per season, see below.
#
# ## Why the dev set is per-season too (this reverses prereqs item 11)
#
# Item 11 made the dev shortcuts single, pointed at the unnumbered repo, on the
# reasoning that "you never rebuild a frozen archived season". That is true at
# Phase 3 and **false for the whole Phase 1 -> 2 overlap**: at Phase 1 the
# OUTGOING season is copied out to _s<N> and keeps serving every player on port
# 5121, so the archive repo is the LIVE server and is precisely the one that may
# need an urgent hotfix (guide 5a says so explicitly). It is frozen by policy,
# not by circumstance.
#
# Meanwhile the unnumbered repo's shortcuts silently changed meaning: after
# Phase 1 "Repack Homer's LotR Module" builds the EARLY-ACCESS season, with
# nothing in its label saying so. An unlabelled button that used to rebuild the
# live server and now rebuilds a test realm is a footgun, and the reverse
# (needing to hotfix live with no shortcut for it) is worse.
#
# So every entry is season-labelled and season-scoped. The nwn_manager wrappers
# take `--project`; the wiki and nwsync scripts are used from the target repo's
# own bin/ (both derive PROJECT from BASH_SOURCE, so they are relocatable).
# NOTE: nwn_manager/bin/refresh-homers-lotr-wiki still hard-codes the unnumbered
# repo and has no --project, so it is deliberately NOT used here.
#
# Lifecycle: Phase 1 installs the new environment's set; Phase 3 removes the
# retired season's set plus its monitor autostart.
#
# Usage:
#   bin/season-shortcuts.sh              # dry run — show what would be written
#   bin/season-shortcuts.sh --install    # write them
#   bin/season-shortcuts.sh --remove     # delete this season's set
#
# Names are season-labelled from server.env, so two sets are tellable apart in
# the app grid, e.g. "Restart Homer's LotR - Season 1 (live)".
set -euo pipefail

PROJECT_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
INSTANCE=$(basename "$PROJECT_ROOT")
APPS="$HOME/.local/share/applications"
AUTOSTART="$HOME/.config/autostart"

MODE=dry
for a in "$@"; do
  case "$a" in
    --install) MODE=install ;;
    --remove)  MODE=remove ;;
    -h|--help) sed -n '2,28p' "${BASH_SOURCE[0]}" | sed 's/^# \?//'; exit 0 ;;
    *) echo "error: unknown arg: $a" >&2; exit 2 ;;
  esac
done

[[ -f $PROJECT_ROOT/server.env ]] || { echo "error: no server.env in $PROJECT_ROOT" >&2; exit 1; }
# shellcheck disable=SC1091
. "$PROJECT_ROOT/server.env"

# Season 1 predates the numbering and keeps the unnumbered filenames, so its
# existing shortcuts stay where they are rather than being duplicated.
if [[ ${SEASON_NUM:-} == 1 ]]; then
  PREFIX="nwn-homers-lotr"
  MON="homers-lotr-monitor"
else
  PREFIX="nwn-homers-lotr-s${SEASON_NUM:-x}"
  MON="homers-lotr-monitor-s${SEASON_NUM:-x}"
fi
LABEL="Season ${SEASON_NUM:-?} (${SEASON_ROLE:-?})"

RESTART="$APPS/$PREFIX-server.desktop"
STOP="$APPS/$PREFIX-server-stop.desktop"
MONITOR="$APPS/$MON.desktop"
MONITOR_AUTO="$AUTOSTART/$MON.desktop"

# Dev entries are always season-suffixed, even for season 1 — unlike the ops
# entries above, season 1 had no per-season dev files to preserve, and leaving
# them unlabelled is the ambiguity this set exists to remove.
DEV_PREFIX="nwn-homers-lotr-s${SEASON_NUM:-x}"
LOGS="$APPS/$DEV_PREFIX-logs.desktop"
UNPACK="$APPS/$DEV_PREFIX-unpack.desktop"
REPACK="$APPS/$DEV_PREFIX-repack.desktop"
REPACK_CLEAN="$APPS/$DEV_PREFIX-repack-clean.desktop"
REPACK_TEST="$APPS/$DEV_PREFIX-repack-test.desktop"
WIKI="$APPS/$DEV_PREFIX-wiki.desktop"
NWSYNC="$APPS/$DEV_PREFIX-refresh-nwsync.desktop"
NWSYNC_FORCE="$APPS/$DEV_PREFIX-refresh-nwsync-force.desktop"

OPS_FILES=("$RESTART" "$STOP" "$MONITOR" "$MONITOR_AUTO" "$LOGS")
DEV_FILES=("$UNPACK" "$REPACK" "$REPACK_CLEAN" "$REPACK_TEST" "$WIKI"
           "$NWSYNC" "$NWSYNC_FORCE")

# The nwn_manager wrappers that accept --project.
MGR="${NWN_MANAGER_BIN:-/var/home/james/GIT/nwn_manager}/bin"

echo "season instance : $INSTANCE"
echo "label           : $LABEL"
echo "ops files       :"
printf '  %s\n' "${OPS_FILES[@]}"
echo "dev files       :"
printf '  %s\n' "${DEV_FILES[@]}"
echo

if [[ $MODE == remove ]]; then
  rm -fv "${OPS_FILES[@]}" "${DEV_FILES[@]}"
  update-desktop-database "$APPS" 2>/dev/null || true
  echo "done. (The roadmap editor is untouched — it is single-instance and tracks"
  echo "the newest repo; see season-cutover-prereqs.md item 12.)"
  exit 0
fi

if [[ $MODE == dry ]]; then
  echo "DRY RUN — re-run with --install to write, --remove to delete."
  exit 0
fi

mkdir -p "$APPS" "$AUTOSTART"

write_entry() {  # $1=path $2=name $3=generic $4=comment $5=exec $6=icon $7=categories $8=extra
  cat > "$1" <<EOF
[Desktop Entry]
Type=Application
Version=1.0
Name=$2
GenericName=$3
Comment=$4
Exec=ptyxis --new-window -- $5
Icon=$6
Terminal=false
Categories=$7
StartupNotify=true
$8
EOF
  echo "wrote $1"
}

# Same, but the Exec is run verbatim (no terminal wrapper) — for xdg-open.
write_raw_entry() {  # $1=path $2=name $3=generic $4=comment $5=exec $6=icon $7=categories
  cat > "$1" <<EOF
[Desktop Entry]
Type=Application
Version=1.0
Name=$2
GenericName=$3
Comment=$4
Exec=$5
Icon=$6
Terminal=false
Categories=$7
StartupNotify=true
EOF
  echo "wrote $1"
}

# A dev task that prints and exits needs the window held open, or the output is
# gone before you can read it.
write_hold_entry() {  # $1=path $2=name $3=generic $4=comment $5=command $6=icon $7=categories
  write_entry "$1" "$2" "$3" "$4" \
    "bash -lc '$5; echo; read -rp \"Press Enter to close...\"'" \
    "$6" "$7" ""
}

write_entry "$RESTART" \
  "Restart Homer's LotR Server - $LABEL" \
  "NWN Dedicated Server" \
  "Cleanly restart this season's Homer's LotR dedicated server via its systemd service. Players are disconnected and can reconnect after ~40s. (The server also starts on its own at boot.)" \
  "$PROJECT_ROOT/bin/server-restart" \
  "steam_icon_704450" "Game;Network;" ""

write_entry "$STOP" \
  "Shut Down Homer's LotR Server - $LABEL" \
  "NWN Dedicated Server" \
  "Cleanly shut down this season's Homer's LotR dedicated server via its systemd service. Players are disconnected; it restarts on the next boot." \
  "$PROJECT_ROOT/bin/server-stop" \
  "steam_icon_704450" "Game;Network;" ""

write_entry "$MONITOR" \
  "Homer's LotR Server Monitor - $LABEL" \
  "NWN Server Live Log" \
  "Watch this season's running server (players, DM messages, errors). Read-only — closing it does not stop the server." \
  "$PROJECT_ROOT/bin/watch-server" \
  "utilities-terminal" "Game;Network;Monitor;" \
  "Keywords=nwn;neverwinter;server;log;monitor;homer;lotr;season${SEASON_NUM:-};"

write_entry "$MONITOR_AUTO" \
  "Homer's LotR Server Monitor - $LABEL" \
  "NWN Server Live Log" \
  "Auto-open this season's live server view on login. Read-only — closing it does not stop the server." \
  "$PROJECT_ROOT/bin/watch-server" \
  "utilities-terminal" "Game;Network;Monitor;" \
  "X-GNOME-Autostart-enabled=true"

# The live server logs are in the RUN dir (nwserver runs with
# -userdirectory /nwn/run), not the home dir. The pre-season shortcut opened
# "$NWN_HOME_DIR/logs", which holds only a couple of stale files and does not
# exist at all in a fresh season's home dir.
write_raw_entry "$LOGS" \
  "NWN Logs - $LABEL" \
  "NWN Server Logs" \
  "Open this season's server log folder (logs.0 is the live one)." \
  "xdg-open \"$NWN_RUN_DIR/logs.0\"" \
  "folder" "Game;Network;Monitor;"

# ---------------------------------------------------------------- dev set ---
write_hold_entry "$UNPACK" \
  "Unpack Homer's LotR Module - $LABEL" \
  "NWN Module Build" \
  "Unpack this season's .mod into unpacked/ (OVERWRITES it — commit first)." \
  "$MGR/refresh-homers-lotr --project \"$PROJECT_ROOT\"" \
  "package-x-generic" "Development;"

write_hold_entry "$REPACK" \
  "Repack Homer's LotR Module - $LABEL" \
  "NWN Module Build" \
  "Build this season's unpacked/ into its .mod and install it. Restart the server to load it." \
  "$MGR/repack-homers-lotr --project \"$PROJECT_ROOT\"" \
  "package-x-generic" "Development;"

write_hold_entry "$REPACK_CLEAN" \
  "Repack Homer's LotR Module (Clean) - $LABEL" \
  "NWN Module Build" \
  "Repack this season from scratch, discarding the nasher build cache." \
  "$MGR/repack-homers-lotr-clean --project \"$PROJECT_ROOT\"" \
  "package-x-generic" "Development;"

write_hold_entry "$REPACK_TEST" \
  "Repack Homer's LotR Module (Testing) - $LABEL" \
  "NWN Module Build" \
  "Repack this season WITHOUT installing to the production modules folder (--no-prod)." \
  "$MGR/repack-homers-lotr --project \"$PROJECT_ROOT\" --no-prod" \
  "package-x-generic" "Development;"

# This season's own bin/, not nwn_manager's copy: the repo-local script derives
# PROJECT from BASH_SOURCE and reads this season's SEASON_WIKI_URL / NWN_RUN_DIR,
# whereas nwn_manager/bin/refresh-homers-lotr-wiki still hard-codes the
# unnumbered repo and has no --project flag.
write_hold_entry "$WIKI" \
  "Regenerate Homer's LotR Wiki - $LABEL" \
  "NWN Module Wiki" \
  "Regenerate this season's docs/ wiki. Expensive — the daily refresh normally does this." \
  "\"$PROJECT_ROOT/bin/refresh-homers-lotr-wiki\"" \
  "text-html" "Development;"

write_hold_entry "$NWSYNC" \
  "Refresh Homer's LotR NWSync - $LABEL" \
  "NWN NWSync Repository" \
  "Rebuild this season's NWSync manifest so clients can download its haks." \
  "\"$PROJECT_ROOT/bin/refresh-nwsync\"" \
  "folder-remote" "Development;Network;"

write_hold_entry "$NWSYNC_FORCE" \
  "Refresh Homer's LotR NWSync (FORCE rebuild) - $LABEL" \
  "NWN NWSync Repository" \
  "Force a full rebuild of this season's NWSync manifest. Slow (hashes every hak)." \
  "\"$PROJECT_ROOT/bin/refresh-nwsync\" --force" \
  "folder-remote" "Development;Network;"

update-desktop-database "$APPS" 2>/dev/null || true
echo
echo "done. Every entry is season-labelled and season-scoped. The roadmap editor"
echo "is untouched: single-instance on the newest repo (prereqs item 12)."

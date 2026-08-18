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

# The dev realm is keyed on its ROLE, not its number. It is permanent and never
# a season, but it carries SEASON_NUM = whichever season it currently feeds — so
# a number-keyed prefix would give dev and that season's production repo the
# SAME .desktop filenames, and whichever ran --install last would silently own
# every button. Role first, number second (same rule as the OneDrive build dir
# in nwn_manager/bin/repack-project.sh).
#
# Season 1 used to keep unnumbered filenames, matching its legacy module name.
# Both are gone: every realm is named uniformly now (Homer's LOTR Season <N>,
# or Homer's LOTR TEST), so every shortcut set is named the same way too.
if [[ ${SEASON_ROLE:-} == dev ]]; then
  PREFIX="nwn-homers-lotr-test"
  MON="homers-lotr-monitor-test"
else
  PREFIX="nwn-homers-lotr-s${SEASON_NUM:-x}"
  MON="homers-lotr-monitor-s${SEASON_NUM:-x}"
fi
if [[ ${SEASON_ROLE:-} == dev ]]; then
  LABEL="TEST realm"
else
  LABEL="Season ${SEASON_NUM:-?} (${SEASON_ROLE:-?})"
fi

RESTART="$APPS/$PREFIX-server.desktop"
STOP="$APPS/$PREFIX-server-stop.desktop"
MONITOR="$APPS/$MON.desktop"
MONITOR_AUTO="$AUTOSTART/$MON.desktop"

# Build/dev entries are always environment-suffixed, even for season 1 — unlike
# the ops entries above, season 1 had no per-season dev files to preserve, and
# leaving them unlabelled is the ambiguity this set exists to remove.
if [[ ${SEASON_ROLE:-} == dev ]]; then
  DEV_PREFIX="nwn-homers-lotr-test"
else
  DEV_PREFIX="nwn-homers-lotr-s${SEASON_NUM:-x}"
fi
LOGS="$APPS/$DEV_PREFIX-logs.desktop"
UNPACK="$APPS/$DEV_PREFIX-unpack.desktop"
REPACK="$APPS/$DEV_PREFIX-repack.desktop"
REPACK_CLEAN="$APPS/$DEV_PREFIX-repack-clean.desktop"
REPACK_TEST="$APPS/$DEV_PREFIX-repack-test.desktop"
WIKI="$APPS/$DEV_PREFIX-wiki.desktop"
NWSYNC="$APPS/$DEV_PREFIX-refresh-nwsync.desktop"
NWSYNC_FORCE="$APPS/$DEV_PREFIX-refresh-nwsync-force.desktop"

# Promotion buttons — DEV REALM ONLY. bin/season-promote.sh refuses to run from
# anywhere but dev, so giving a season's folder a "Promote to Prod" tile would
# only ever produce an error, and next to a live season's Shut Down button that
# is a tile nobody should be tempted to click. One per override, because the
# overrides are exactly what is easy to get wrong under time pressure.
PROMOTE_FILES=()
if [[ ${SEASON_ROLE:-} == dev ]]; then
  PROMOTE_DRY="$APPS/$DEV_PREFIX-promote-dry.desktop"
  PROMOTE="$APPS/$DEV_PREFIX-promote.desktop"
  PROMOTE_HOT="$APPS/$DEV_PREFIX-promote-hot.desktop"
  PROMOTE_FAST="$APPS/$DEV_PREFIX-promote-fast.desktop"
  PROMOTE_NOBUILD="$APPS/$DEV_PREFIX-promote-nobuild.desktop"
  PROMOTE_FILES=("$PROMOTE_DRY" "$PROMOTE" "$PROMOTE_HOT" "$PROMOTE_FAST"
                 "$PROMOTE_NOBUILD")
fi

OPS_FILES=("$RESTART" "$STOP" "$MONITOR" "$MONITOR_AUTO" "$LOGS")
DEV_FILES=("$UNPACK" "$REPACK" "$REPACK_CLEAN" "$REPACK_TEST" "$WIKI"
           "$NWSYNC" "$NWSYNC_FORCE" "${PROMOTE_FILES[@]}")

# ## The app-grid folder — one tile per season, not eleven loose icons
#
# Two seasons' sets are near-identical (same icons, same labels bar the trailing
# realm tag) and one of the buttons is "Shut Down Server". On 2026-08-13 the TEST
# set was left unfoldered beside Season 2's folder and the wrong Shut Down was
# clicked: dev went down, live season 2 stayed up. Foldering keeps the live stop
# button away from the test one, so it ships with the shortcuts rather than being
# a thing to tidy up afterwards.
#
# MONITOR_AUTO is deliberately absent: it is an autostart file in ~/.config/
# autostart, not an app-grid entry. Order here is the order in the folder.
FOLDER_APPS=("$(basename "$RESTART")" "$(basename "$STOP")" "$(basename "$MONITOR")"
             "$(basename "$REPACK")" "$(basename "$REPACK_TEST")"
             "$(basename "$REPACK_CLEAN")" "$(basename "$UNPACK")"
             "$(basename "$WIKI")" "$(basename "$NWSYNC")"
             "$(basename "$NWSYNC_FORCE")" "$(basename "$LOGS")")
# Promotion tiles go LAST in the folder, after the everyday build buttons: they
# are the only ones here that change another realm.
for f in "${PROMOTE_FILES[@]}"; do FOLDER_APPS+=("$(basename "$f")"); done
if [[ ${SEASON_ROLE:-} == dev ]]; then
  FOLDER_ID="nwn-test"
  FOLDER_NAME="TEST realm NWN"
else
  FOLDER_ID="nwn-s${SEASON_NUM:-x}"
  FOLDER_NAME="Season ${SEASON_NUM:-?} NWN"
fi
# Season 1 predates this and lives in a folder called `NWN`; season 2's was made
# by hand in the GNOME UI and carries a UUID. season-appfolder.py adopts whatever
# folder already holds our entries rather than minting a second one, so FOLDER_ID
# only ever applies to a season that has no folder yet.
appfolder() {  # $1 = --apply | --remove
  local helper="$PROJECT_ROOT/bin/season-appfolder.py"
  [[ -x $helper || -f $helper ]] || { echo "note: $helper missing — no app folder"; return 0; }
  python3 "$helper" --id "$FOLDER_ID" --name "$FOLDER_NAME" \
    "$1" --apps "${FOLDER_APPS[@]}" || echo "note: app folder step failed (shortcuts are still installed)"
}

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
  appfolder --remove
  update-desktop-database "$APPS" 2>/dev/null || true
  echo "done. (The roadmap editor is untouched — it is single-instance and tracks"
  echo "the newest repo; see season-cutover-prereqs.md item 12.)"
  exit 0
fi

echo "app folder      : $FOLDER_NAME (id $FOLDER_ID)"
echo

if [[ $MODE == dry ]]; then
  # The helper is dry-run by default too, so this previews the folder change.
  python3 "$PROJECT_ROOT/bin/season-appfolder.py" --id "$FOLDER_ID" \
    --name "$FOLDER_NAME" --apps "${FOLDER_APPS[@]}" || true
  echo
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

# NO per-season autostart entry any more. Two reasons it is gone:
#
#  1. It never worked. gnome-session fires XDG autostart before
#     xdg-desktop-portal owns its bus name, and ptyxis needs the portal: every
#     boot logged "Failed to register: Timeout was reached", ptyxis dumped core,
#     and the monitors had to be started by hand. Three simultaneous ptyxis
#     launches at t+0 also raced to be the primary instance.
#  2. Three windows for three realms was the wrong shape anyway.
#
# Replaced by ONE cross-realm window: bin/watch-all-servers, launched by
# systemd/nwn-monitor-all.service (ordered after the portal), installed by
# bin/monitor-all-shortcut.sh. It is not per season, so it is not written here.
#
# $MONITOR_AUTO stays in OPS_FILES below so --remove still cleans up any stale
# file a pre-2026-08-14 install left behind.

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

# ---------------------------------------------------------------- promotion --
# Dev realm only (PROMOTE_FILES is empty elsewhere). bin/promote-to-prod finds
# the live season itself and makes you type its number back, so the tile carries
# no season in its Exec and cannot go stale after a cutover.
if ((${#PROMOTE_FILES[@]})); then
  write_hold_entry "$PROMOTE_DRY" \
    "Promote to Prod - DRY RUN" \
    "NWN Season Promotion" \
    "Preview what promoting this dev tree to the live season would change. Writes nothing. Always safe - start here." \
    "\"$PROJECT_ROOT/bin/promote-to-prod\" dry" \
    "document-print-preview" "Development;"

  write_hold_entry "$PROMOTE" \
    "Promote to Prod" \
    "NWN Season Promotion" \
    "Promote this dev tree to the live season and rebuild its module. For a target whose server is STOPPED. Asks you to confirm the season number." \
    "\"$PROJECT_ROOT/bin/promote-to-prod\" apply" \
    "software-update-available" "Development;"

  write_hold_entry "$PROMOTE_HOT" \
    "Promote to Prod (server running)" \
    "NWN Season Promotion" \
    "As Promote to Prod, but for a live season whose server is UP (--allow-hot). The new module is installed under the running server and takes effect at its next restart." \
    "\"$PROJECT_ROOT/bin/promote-to-prod\" hot" \
    "software-update-urgent" "Development;"

  write_hold_entry "$PROMOTE_FAST" \
    "Promote to Prod (fast NWSync + reboot)" \
    "NWN Season Promotion" \
    "Promote, rebuild the target's hak, verify it publishes the same content as dev, then arm reboot-on-empty to COPY dev's manifest during the down window - seconds instead of a ~20 minute rebuild. Use when the hak changed. Prompts for the message players see." \
    "\"$PROJECT_ROOT/bin/promote-to-prod\" fast" \
    "clock" "Development;"

  write_hold_entry "$PROMOTE_NOBUILD" \
    "Promote to Prod (no rebuild)" \
    "NWN Season Promotion" \
    "Sync and rebrand the target only - no repack. For a change that touches tooling or docs but not the module." \
    "\"$PROJECT_ROOT/bin/promote-to-prod\" nobuild" \
    "emblem-synchronizing" "Development;"
fi

update-desktop-database "$APPS" 2>/dev/null || true
echo
appfolder --apply
echo
echo "done. Every entry is season-labelled, season-scoped, and in this season's"
echo "own app-grid folder. The roadmap editor is untouched: single-instance on"
echo "the newest repo (prereqs item 12)."

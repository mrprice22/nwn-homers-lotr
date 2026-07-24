#!/usr/bin/env bash
# Install / remove THIS season's ops app-grid shortcuts (restart, stop, monitor)
# and its monitor autostart entry.
#
# App-grid entries split by purpose (season-cutover-prereqs.md item 11):
#
#   DEV shortcuts   unpack / repack / repack-clean / repack-test / wiki /
#                   refresh-nwsync — SINGLE, always pointed at the unnumbered
#                   repo, which is always the newest season. You never rebuild a
#                   frozen archived season, so these are not per-season and this
#                   script does not touch them.
#
#   OPS shortcuts   restart / stop / monitor — PER SEASON, because during a
#                   cutover overlap two servers are running and each needs its
#                   own. Each set's Exec points at its own repo's bin/, so the
#                   season is implied by the path and they take no arguments.
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

echo "season instance : $INSTANCE"
echo "label           : $LABEL"
echo "files           :"
printf '  %s\n' "$RESTART" "$STOP" "$MONITOR" "$MONITOR_AUTO"
echo

if [[ $MODE == remove ]]; then
  rm -fv "$RESTART" "$STOP" "$MONITOR" "$MONITOR_AUTO"
  update-desktop-database "$APPS" 2>/dev/null || true
  echo "done. (Dev shortcuts and the roadmap editor are untouched — they track"
  echo "the newest repo and never pointed at this season.)"
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

update-desktop-database "$APPS" 2>/dev/null || true
echo
echo "done. Dev shortcuts (unpack/repack/wiki/nwsync) are unchanged — they stay"
echo "pointed at the unnumbered repo, which is always the newest season."

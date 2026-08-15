#!/usr/bin/env bash
# Install / remove the CROSS-REALM server monitor: the app-grid tile and the
# login autostart unit for bin/watch-all-servers.
#
# Unlike bin/season-shortcuts.sh this is deliberately NOT per season -- there is
# one combined monitor for the whole box, the same way there is one roadmap
# editor (season-cutover-prereqs.md item 12). It lives in the unnumbered dev repo
# and no season phase creates or retires it.
#
# It also cleans up the three per-season autostart entries season-shortcuts.sh
# used to write, which never survived a login (see systemd/nwn-monitor-all.service
# for the boot journal showing why). The per-season app-grid "Server Monitor"
# TILES are left alone -- watching one realm on its own is still useful.
#
# Usage:
#   bin/monitor-all-shortcut.sh              # dry run — show what would change
#   bin/monitor-all-shortcut.sh --install    # write + enable
#   bin/monitor-all-shortcut.sh --remove     # delete + disable
set -euo pipefail

PROJECT_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
APPS="$HOME/.local/share/applications"
AUTOSTART="$HOME/.config/autostart"
UNITS="$HOME/.config/systemd/user"

UNIT_NAME="nwn-monitor-all.service"
UNIT_SRC="$PROJECT_ROOT/systemd/$UNIT_NAME"
UNIT_DST="$UNITS/$UNIT_NAME"
TILE="$APPS/homers-lotr-monitor-all.desktop"
WATCH="$PROJECT_ROOT/bin/watch-all-servers"
# What the unit runs: the retrying, idempotent wrapper, not ptyxis directly.
LAUNCH="$PROJECT_ROOT/bin/monitor-window"

# The per-season autostart files this replaces. Any season that still has one
# would open a redundant single-realm window (and hit the same portal race).
LEGACY_AUTOSTART=(
  "$AUTOSTART/homers-lotr-monitor-test.desktop"
  "$AUTOSTART/homers-lotr-monitor-s1.desktop"
  "$AUTOSTART/homers-lotr-monitor-s2.desktop"
)

MODE=dry
for a in "$@"; do
  case "$a" in
    --install) MODE=install ;;
    --remove)  MODE=remove ;;
    -h|--help) sed -n '2,20p' "${BASH_SOURCE[0]}" | sed 's/^# \?//'; exit 0 ;;
    *) echo "error: unknown arg: $a" >&2; exit 2 ;;
  esac
done

[[ -x $WATCH ]] || { echo "error: $WATCH missing or not executable" >&2; exit 1; }
[[ -x $LAUNCH ]] || { echo "error: $LAUNCH missing or not executable" >&2; exit 1; }
[[ -f $UNIT_SRC ]] || { echo "error: $UNIT_SRC missing" >&2; exit 1; }

echo "monitor script  : $WATCH"
echo "window launcher : $LAUNCH"
echo "app tile        : $TILE"
echo "autostart unit  : $UNIT_DST"
echo "legacy autostart:"
for f in "${LEGACY_AUTOSTART[@]}"; do
  [[ -e $f ]] && echo "  $f (present — will be removed)" || echo "  $f (absent)"
done
echo

if [[ $MODE == dry ]]; then
  echo "DRY RUN — re-run with --install to write, --remove to delete."
  exit 0
fi

if [[ $MODE == remove ]]; then
  systemctl --user disable --now "$UNIT_NAME" 2>/dev/null || true
  rm -fv "$UNIT_DST" "$TILE"
  systemctl --user daemon-reload
  update-desktop-database "$APPS" 2>/dev/null || true
  echo "done. (bin/watch-all-servers itself is untouched — run it from a terminal"
  echo "any time. Per-season monitor tiles are untouched too.)"
  exit 0
fi

mkdir -p "$APPS" "$UNITS"

# The unit hard-codes this repo's path, so rewrite it on install rather than
# assuming the checkout lives where the committed copy says.
sed "s#/var/home/james/GIT/nwn_homers_lotr#$PROJECT_ROOT#g" "$UNIT_SRC" > "$UNIT_DST"
echo "wrote $UNIT_DST"

cat > "$TILE" <<EOF
[Desktop Entry]
Type=Application
Version=1.0
Name=Homer's LotR Server Monitor - All Realms
GenericName=NWN Server Live Log
Comment=Watch every realm's running server at once (test, live season, archived season) in one colour-tagged stream. Read-only — closing it does not stop any server.
Exec=ptyxis --new-window -- $WATCH
Icon=utilities-terminal
Terminal=false
Categories=Game;Network;Monitor;
StartupNotify=true
Keywords=nwn;neverwinter;server;log;monitor;homer;lotr;all;realms;combined;
EOF
echo "wrote $TILE"

# Deliberately NOT filed into a per-season app folder (season-shortcuts.sh's
# nwn-test / nwn-s<N>): it belongs to no season, and the wrong-button hazard that
# motivated foldering was "Shut Down Server", which this is not.
rm -fv "${LEGACY_AUTOSTART[@]}" 2>/dev/null || true

systemctl --user daemon-reload
systemctl --user enable "$UNIT_NAME"
update-desktop-database "$APPS" 2>/dev/null || true

echo
echo
echo "done. The window opens at the next login/reboot. To open one now:"
echo "  systemctl --user start $UNIT_NAME"
echo "Is one open? $LAUNCH --check"

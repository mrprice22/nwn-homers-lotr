#!/usr/bin/env bash
# Install / remove this season's systemd user units.
#
# The season instance name is this repo's DIRECTORY NAME, so the units a repo
# drives are implied by where the repo lives — no arguments, nothing to keep in
# sync by hand:
#
#   ~/GIT/nwn_homers_lotr      -> nwn-season-server@nwn_homers_lotr.service
#   ~/GIT/nwn_homers_lotr_s1   -> nwn-season-server@nwn_homers_lotr_s1.service
#
# What it writes:
#   ~/.config/nwn-season/<instance>.env          instance env (container, run dir, project)
#   ~/.config/systemd/user/nwn-season-*@.service symlinks to this repo's systemd/ templates
#   ~/.config/systemd/user/nwn-season-empty-restart@<instance>.path
#                                                rendered (a .path unit cannot expand env vars)
#
# Usage:
#   bin/season-units.sh                 # dry run — show what would change
#   bin/season-units.sh --install       # write + daemon-reload (does NOT enable or start)
#   bin/season-units.sh --enable        # --install, then enable the server/backup/wiki/path units
#   bin/season-units.sh --remove        # disable + remove THIS instance's units and env file
#
# Enabling is deliberately a separate step: installing the units next to the old
# homers-lotr-*.service ones is harmless, so you can stage the change and only
# flip over when you're ready. Nothing here starts or stops a running server.
set -euo pipefail

PROJECT_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
INSTANCE=$(basename "$PROJECT_ROOT")
UNIT_DIR="$HOME/.config/systemd/user"
ENV_DIR="$HOME/.config/nwn-season"
SRC="$PROJECT_ROOT/systemd"

# Templates symlinked as-is. The .path is rendered separately (see below).
TEMPLATES=(
  "nwn-season-server@.service"
  "nwn-season-backup@.service"
  "nwn-season-wiki-publish@.service"
  "nwn-season-empty-restart@.service"
  "nwn-season-vault-sync@.service"
  "nwn-season-vault-sync@.timer"
  "nwn-season-online-push@.service"
  "nwn-season-online-push@.timer"
)
# Shared @ template drop-ins. NOTE: nwn-season-server@.service.d is deliberately
# NOT here -- the server's priority drop-in is rendered PER INSTANCE below,
# because a shared one applied the dev realm's weights to the live season (see
# systemd/nwn-season-server@.service.d.priority.conf.in for the full story).
DROPINS=(
  "nwn-season-wiki-publish@.service.d"
)
# Units enabled by --enable. The empty-restart .service is triggered by the
# .path, so it is not enabled itself.
ENABLE_UNITS=(
  "nwn-season-server@$INSTANCE.service"
  "nwn-season-backup@$INSTANCE.service"
  "nwn-season-wiki-publish@$INSTANCE.service"
  "nwn-season-empty-restart@$INSTANCE.path"
)
MODE=dry
for a in "$@"; do
  case "$a" in
    --install) MODE=install ;;
    --enable)  MODE=enable ;;
    --remove)  MODE=remove ;;
    -h|--help) sed -n '2,28p' "${BASH_SOURCE[0]}" | sed 's/^# \?//'; exit 0 ;;
    *) echo "error: unknown arg: $a" >&2; exit 2 ;;
  esac
done

[[ -f $PROJECT_ROOT/server.env ]] || { echo "error: no server.env in $PROJECT_ROOT" >&2; exit 1; }
# shellcheck disable=SC1091
. "$PROJECT_ROOT/server.env"
: "${NWN_CONTAINER_NAME:?NWN_CONTAINER_NAME unset in server.env}"
: "${NWN_RUN_DIR:?NWN_RUN_DIR unset in server.env}"

# The units use %h/GIT/%i for WorkingDirectory and ExecStart, so a repo parked
# anywhere else would silently drive the wrong (or no) directory.
if [[ $PROJECT_ROOT != "$HOME/GIT/$INSTANCE" && $PROJECT_ROOT != "$(readlink -f "$HOME/GIT/$INSTANCE" 2>/dev/null)" ]]; then
  echo "error: the templates resolve %h/GIT/%i = $HOME/GIT/$INSTANCE," >&2
  echo "       but this repo is at $PROJECT_ROOT." >&2
  echo "       Season repos must live directly under ~/GIT/ (see season-cutover-guide.md)." >&2
  exit 1
fi

PATH_UNIT="nwn-season-empty-restart@$INSTANCE.path"

# The prod->dev character vault sync only ever writes INTO a dev realm, so its
# timer is armed for the dev instance alone. The template is still installed
# everywhere (they are shared, and bin/sync-vault-from-prod refuses to run
# outside dev anyway) - this just keeps a live/archive season from carrying a
# timer that could only ever refuse.
if [[ ${SEASON_ROLE:-} == dev ]]; then
  ENABLE_UNITS+=("nwn-season-vault-sync@$INSTANCE.timer")
fi

# The who's-online pusher is armed wherever a push URL is configured, NOT by
# role. That is deliberate: the live season is the realm that should normally
# publish a roster, but the dev realm has to be able to switch it on to test the
# pipeline end to end before it ships. With SEASON_STATUS_PUSH_URL empty the
# script exits cleanly anyway, so the timer is merely pointless rather than
# harmful -- this just avoids installing a timer that could only ever no-op.
if [[ -n ${SEASON_STATUS_PUSH_URL:-} ]]; then
  ENABLE_UNITS+=("nwn-season-online-push@$INSTANCE.timer")
fi

echo "season instance : $INSTANCE"
echo "project         : $PROJECT_ROOT"
echo "season          : num='${SEASON_NUM:-unset}' role='${SEASON_ROLE:-unset}'"
echo "container       : $NWN_CONTAINER_NAME"
echo "run dir         : $NWN_RUN_DIR"
echo "watch path      : $NWN_RUN_DIR/anvil/PluginData/restart-server"
echo

if [[ $MODE == remove ]]; then
  for u in "${ENABLE_UNITS[@]}"; do
    systemctl --user disable --now "$u" 2>/dev/null || true
    echo "  disabled $u"
  done
  rm -fv "$UNIT_DIR/$PATH_UNIT" "$ENV_DIR/$INSTANCE.env"
  rm -rfv "${UNIT_DIR:?}/nwn-season-server@$INSTANCE.service.d"
  # Templates are shared by every instance — only drop them if no instance env
  # files remain.
  if ! compgen -G "$ENV_DIR/*.env" >/dev/null; then
    for t in "${TEMPLATES[@]}"; do rm -fv "$UNIT_DIR/$t"; done
    for d in "${DROPINS[@]}"; do rm -rfv "${UNIT_DIR:?}/$d"; done
  else
    echo "  (kept shared @ templates — other season instances still configured)"
  fi
  systemctl --user daemon-reload
  echo "done."
  exit 0
fi

if [[ $MODE == dry ]]; then
  echo "DRY RUN — would write:"
  echo "  $ENV_DIR/$INSTANCE.env"
  for t in "${TEMPLATES[@]}"; do echo "  $UNIT_DIR/$t -> $SRC/$t"; done
  for d in "${DROPINS[@]}"; do echo "  $UNIT_DIR/$d/ (drop-ins)"; done
  echo "  $UNIT_DIR/nwn-season-server@$INSTANCE.service.d/priority.conf (rendered, role=${SEASON_ROLE:-unset})"
  echo "  $UNIT_DIR/$PATH_UNIT (rendered)"
  echo
  echo "then: systemctl --user daemon-reload"
  echo "re-run with --install to write, or --enable to write and enable:"
  printf '  %s\n' "${ENABLE_UNITS[@]}"
  exit 0
fi

mkdir -p "$UNIT_DIR" "$ENV_DIR"

# --- instance env file ------------------------------------------------------
# Only what the units themselves need. Everything else stays in server.env,
# which the scripts source for themselves.
cat > "$ENV_DIR/$INSTANCE.env" <<EOF
# Generated by bin/season-units.sh from $PROJECT_ROOT/server.env — do not edit.
# Re-run bin/season-units.sh --install after changing server.env.
PROJECT_ROOT=$PROJECT_ROOT
NWN_CONTAINER_NAME=$NWN_CONTAINER_NAME
NWN_RUN_DIR=$NWN_RUN_DIR
SEASON_NUM=${SEASON_NUM:-}
SEASON_ROLE=${SEASON_ROLE:-}
EOF
echo "wrote $ENV_DIR/$INSTANCE.env"

# --- shared @ templates (symlinked, so a repo edit takes effect on reload) ---
for t in "${TEMPLATES[@]}"; do
  ln -sfn "$SRC/$t" "$UNIT_DIR/$t"
  echo "linked $UNIT_DIR/$t"
done
for d in "${DROPINS[@]}"; do
  mkdir -p "$UNIT_DIR/$d"
  for f in "$SRC/$d"/*.conf; do
    ln -sfn "$f" "$UNIT_DIR/$d/$(basename "$f")"
  done
  echo "linked $UNIT_DIR/$d/"
done

# --- rendered .path ---------------------------------------------------------
# A .path unit cannot expand environment variables, and NWN_RUN_DIR is not
# derivable from %i (season 1 keeps the legacy unnumbered run dir), so this one
# is generated with the literal path baked in.
#
# Validate the layout before baking it in: if this season's run dir has `anvil`
# as the container-only symlink the image entrypoint creates, the rendered unit
# would watch a host path that can never exist and the empty-restart would leave
# the season down. Better to fail at install time than to ship a dead watcher.
# shellcheck source=bin/season-unit.sh
. "$PROJECT_ROOT/bin/season-unit.sh"
season_anvil_dir "$NWN_RUN_DIR" >/dev/null || {
  echo "season-units: refusing to render $PATH_UNIT with a broken Anvil layout" >&2
  exit 1
}

sed -e "s|@INSTANCE@|$INSTANCE|g" -e "s|@RUN_DIR@|$NWN_RUN_DIR|g" \
    "$SRC/nwn-season-empty-restart@.path.in" > "$UNIT_DIR/$PATH_UNIT"
echo "rendered $UNIT_DIR/$PATH_UNIT"

# --- rendered per-instance priority drop-in ---------------------------------
# The live season must outrank the toolchain; the dev realm rides with it.
# Rationale in full: systemd/nwn-season-server@.service.d.priority.conf.in
PRIO_DIR="$UNIT_DIR/nwn-season-server@$INSTANCE.service.d"

# Migration: the old SHARED drop-in pinned every instance -- prod included -- to
# CPUWeight=40, below the default 100. Remove it so the per-instance file wins
# cleanly rather than merging with a stale inversion.
if [[ -e $UNIT_DIR/nwn-season-server@.service.d/priority.conf ]]; then
  rm -fv "$UNIT_DIR/nwn-season-server@.service.d/priority.conf"
  rmdir "$UNIT_DIR/nwn-season-server@.service.d" 2>/dev/null || true
  echo "  (removed the legacy shared priority.conf that deprioritised the live season)"
fi

case "${SEASON_ROLE:-}" in
  live)
    # The only workload on this box with players waiting on it. NWN's main loop
    # is single-threaded, so it cannot absorb scheduling delay by spreading out:
    # a stalled frame IS in-game lag. MemoryLow keeps its working set off the
    # reclaim list when the desktop browser balloons.
    ROLE_COMMENT="# Instance role: LIVE -- players are on this. Outranks everything."
    CPU_WEIGHT=10000; IO_WEIGHT=1000
    EXTRA_LINES=(
      "IOSchedulingClass=realtime"
      "IOSchedulingPriority=0"
      "MemoryLow=1500M"
    )
    ;;
  dev|test)
    # Throttled alongside the build tooling by choice: the admin is normally the
    # only one on it, and it shares a spindle with the repacks that feed it.
    ROLE_COMMENT="# Instance role: DEV/TEST -- rides with the build tooling."
    CPU_WEIGHT=30; IO_WEIGHT=30
    EXTRA_LINES=()
    ;;
  *)
    # archive, or unset: neutral. Never below default -- that is the bug this
    # whole file exists to undo.
    ROLE_COMMENT="# Instance role: ${SEASON_ROLE:-unset} -- neutral (kernel default)."
    CPU_WEIGHT=100; IO_WEIGHT=100
    EXTRA_LINES=()
    ;;
esac

mkdir -p "$PRIO_DIR"
# @EXTRA@ is a placeholder LINE, deleted here and replaced by real settings
# below -- a sed replacement cannot carry embedded newlines.
sed -e "s|@ROLE_COMMENT@|$ROLE_COMMENT|" \
    -e "s|@CPU_WEIGHT@|$CPU_WEIGHT|" \
    -e "s|@IO_WEIGHT@|$IO_WEIGHT|" \
    -e "/@EXTRA@/d" \
    "$SRC/nwn-season-server@.service.d.priority.conf.in" > "$PRIO_DIR/priority.conf"
for line in ${EXTRA_LINES+"${EXTRA_LINES[@]}"}; do
  echo "$line" >> "$PRIO_DIR/priority.conf"
done
echo "rendered $PRIO_DIR/priority.conf (role=${SEASON_ROLE:-unset} cpu=$CPU_WEIGHT io=$IO_WEIGHT)"

systemctl --user daemon-reload
echo "daemon-reload done"

if [[ $MODE == enable ]]; then
  echo
  for u in "${ENABLE_UNITS[@]}"; do
    systemctl --user enable "$u"
  done

  # A .path unit only watches while it is ACTIVE — enabling alone just queues it
  # for the next boot, so reboot-on-empty would silently do nothing until then.
  # Starting a watcher is harmless (unlike starting the server, which stays a
  # deliberate manual step below).
  systemctl --user start "nwn-season-empty-restart@$INSTANCE.path"
  echo "started nwn-season-empty-restart@$INSTANCE.path (watchers only watch while active)"

  # Same story for the vault-sync timer: enable queues it for the next boot, so
  # start it now. It only fires OnBootSec, so starting it mid-session schedules
  # nothing further today -- run bin/sync-vault-from-prod --apply by hand if you
  # want the characters now.
  if [[ ${SEASON_ROLE:-} == dev ]]; then
    systemctl --user start "nwn-season-vault-sync@$INSTANCE.timer"
    echo "started nwn-season-vault-sync@$INSTANCE.timer (prod -> dev character vault sync, once per boot)"
  fi

  echo
  echo "Enabled. The server is NOT started — start it when ready:"
  echo "  systemctl --user start nwn-season-server@$INSTANCE.service"
  echo
  echo "The legacy homers-lotr-* units are still installed. Once this instance is"
  echo "proven across a stop/start and a reboot, disable them — note '--now', or"
  echo "the legacy .path watcher keeps running alongside the new one and both"
  echo "fire on the same flag file:"
  echo "  systemctl --user disable --now homers-lotr-server.service \\"
  echo "      homers-lotr-backup.service homers-lotr-wiki-publish.service \\"
  echo "      homers-lotr-empty-restart.path"
fi

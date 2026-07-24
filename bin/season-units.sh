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
)
DROPINS=(
  "nwn-season-server@.service.d"
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
sed -e "s|@INSTANCE@|$INSTANCE|g" -e "s|@RUN_DIR@|$NWN_RUN_DIR|g" \
    "$SRC/nwn-season-empty-restart@.path.in" > "$UNIT_DIR/$PATH_UNIT"
echo "rendered $UNIT_DIR/$PATH_UNIT"

systemctl --user daemon-reload
echo "daemon-reload done"

if [[ $MODE == enable ]]; then
  echo
  for u in "${ENABLE_UNITS[@]}"; do
    systemctl --user enable "$u"
  done
  echo
  echo "Enabled. The units are NOT started — start the server when ready:"
  echo "  systemctl --user start nwn-season-server@$INSTANCE.service"
  echo
  echo "The legacy homers-lotr-*.service units are still installed. Once this"
  echo "instance is proven across a stop/start and a reboot, disable them:"
  echo "  systemctl --user disable --now homers-lotr-server.service \\"
  echo "      homers-lotr-backup.service homers-lotr-wiki-publish.service \\"
  echo "      homers-lotr-empty-restart.path"
fi

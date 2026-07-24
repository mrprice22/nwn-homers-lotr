#!/usr/bin/env bash
# Move the cross-season campaign DBs to a season-neutral path and symlink them
# back into this season's database/ dir.
#
# Two files persist across EVERY season:
#   meritdb   account merit + redemption entitlements (keyed by CD key)
#   admindb   the CD-key admin whitelist + the player-home fulfilment records
#
# Everything else about a character is fresh each season, and a separate
# NWN_HOME_DIR per season is what gives you that for free. These two must
# survive, so they cannot live inside any season's own directory — retiring that
# season would orphan them. They move to ~/.local/share/nwn-shared/ and each
# season's database/ gets an ABSOLUTE symlink to them (seasons live at different
# depths, so a relative link would break).
#
# See season-cutover-prereqs.md item 2 and season-cutover-guide.md §2.
#
# Usage:
#   bin/season-shared-dbs.sh              # dry run — report what would happen
#   bin/season-shared-dbs.sh --apply      # do it
#
# Idempotent: re-running once the symlinks exist is a clean no-op, so this is
# also the Phase 1 step that links a NEW season's database/ at the shared files.
# Refuses to run while this season's server container is up.
set -euo pipefail

PROJECT_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SHARED_DIR="${NWN_SHARED_DIR:-$HOME/.local/share/nwn-shared}"
DBS=(meritdb admindb)

APPLY=0
for a in "$@"; do
  case "$a" in
    --apply) APPLY=1 ;;
    -h|--help) sed -n '2,25p' "${BASH_SOURCE[0]}" | sed 's/^# \?//'; exit 0 ;;
    *) echo "error: unknown arg: $a" >&2; exit 2 ;;
  esac
done

[[ -f $PROJECT_ROOT/server.env ]] || { echo "error: no server.env in $PROJECT_ROOT" >&2; exit 1; }
# shellcheck disable=SC1091
. "$PROJECT_ROOT/server.env"
: "${NWN_HOME_DIR:?NWN_HOME_DIR unset in server.env}"
DB_DIR="$NWN_HOME_DIR/database"

echo "season      : num=${SEASON_NUM:-unset} role=${SEASON_ROLE:-unset}"
echo "database dir: $DB_DIR"
echo "shared dir  : $SHARED_DIR"
echo

[[ -d $DB_DIR ]] || { echo "error: no database dir at $DB_DIR" >&2; exit 1; }

# A live server holds these files open; moving them out from under it would give
# the running module a stale fd and lose every write made afterwards.
if podman container exists "${NWN_CONTAINER_NAME:-}" 2>/dev/null \
   && [[ $(podman inspect -f '{{.State.Running}}' "$NWN_CONTAINER_NAME" 2>/dev/null) == true ]]; then
  echo "REFUSED: container '$NWN_CONTAINER_NAME' is running." >&2
  echo "         Stop the server first: bin/server-stop" >&2
  exit 3
fi

plan=()
for f in "${DBS[@]}"; do
  src="$DB_DIR/$f.sqlite3"
  dst="$SHARED_DIR/$f.sqlite3"
  if [[ -L $src ]]; then
    target=$(readlink "$src")
    if [[ $target == "$dst" ]]; then
      echo "  $f: already shared -> $target"
    else
      echo "  $f: WARNING symlink points somewhere unexpected -> $target" >&2
    fi
  elif [[ -f $src && -f $dst ]]; then
    echo "  $f: ERROR regular file here AND a shared copy exists — refusing to guess" >&2
    echo "        $src" >&2
    echo "        $dst" >&2
    exit 4
  elif [[ -f $src ]]; then
    echo "  $f: will move -> $dst (+ .bak kept in place)"
    plan+=("$f")
  elif [[ -f $dst ]]; then
    echo "  $f: will link  -> $dst (no local copy; this is a new season)"
    plan+=("$f")
  else
    echo "  $f: ERROR not found in either location" >&2
    exit 4
  fi
done
echo

if [[ ${#plan[@]} -eq 0 ]]; then
  echo "nothing to do — both DBs already shared."
  exit 0
fi

if [[ $APPLY -eq 0 ]]; then
  echo "DRY RUN — re-run with --apply."
  exit 0
fi

mkdir -p "$SHARED_DIR"
for f in "${plan[@]}"; do
  src="$DB_DIR/$f.sqlite3"
  dst="$SHARED_DIR/$f.sqlite3"
  if [[ -f $src && ! -L $src ]]; then
    # Keep a copy on the old path first. Deleting a symlink is recoverable;
    # losing one of these two files is not — no season's backup captures them
    # once they are symlinks (bin/backup-homers-lotr skips links by design).
    cp -p "$src" "$src.bak"
    mv "$src" "$dst"
    echo "moved  $src -> $dst   (backup: $src.bak)"
  fi
  ln -sfn "$dst" "$src"
  echo "linked $src -> $dst"
done

echo
echo "verification:"
ls -l "$DB_DIR"/meritdb.sqlite3 "$DB_DIR"/admindb.sqlite3
for f in "${DBS[@]}"; do
  n=$(sqlite3 "$DB_DIR/$f.sqlite3" "select count(*) from sqlite_master where type='table';" 2>&1)
  echo "  $f: $n tables readable through the symlink"
done
echo
echo "Backup note: bin/backup-homers-lotr now skips symlinked DBs and snapshots"
echo "these two from $SHARED_DIR only when SEASON_ROLE=live."

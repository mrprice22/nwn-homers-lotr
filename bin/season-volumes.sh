#!/usr/bin/env bash
# season-volumes.sh -- refuse to run against a directory whose SSD bind mount
# is not active.  Sourced, never executed.
#
# THE FAILURE THIS EXISTS TO PREVENT
# ----------------------------------
# NWN_RUN_DIR, NWN_HOME_DIR and NWN_SHARED_DIR live on /var/mnt/ssd250 and are
# bind-mounted back to their original $HOME paths by /etc/fstab.  If the SSD
# does not mount, those paths still EXIST -- as empty directories on the HDD.
# bin/serve then runs `mkdir -p "$NWN_RUN_DIR"` and
# `mkdir -p "$NWN_RUN_DIR/anvil/PluginData"`, podman materialises
# "$NWN_RUN_DIR/settings.tml" as a DIRECTORY for its own :Z bind mount, and
# nwserver boots a pristine world: no servervault, no campaign databases, no
# module.  The first player to log in creates a second, divergent character,
# and the next daily backup then snapshots the empty realm over the good one.
#
# fstab cannot prevent this.  `nofail` is deliberate there -- a missing SSD
# must not drop this headless, lingering box into an emergency shell, because
# there is no console to rescue it from.  And `RequiresMountsFor=` only ORDERS:
# systemd adds the dependency for mount units it can resolve, so when the mount
# is absent entirely there is nothing to depend on and the start proceeds.
#
# So the refusal has to live in userspace, here, where it also protects a
# hand-run `bin/serve` outside systemd.
#
# WHY A MARKER FILE AND NOT `mountpoint -q`
# -----------------------------------------
# Three reasons, in order of how much they matter:
#   1. Its CONTENT catches a bind wired to the WRONG season's data -- a
#      mountpoint check cannot tell home-dev from home-s2, and starting the
#      live season against the dev realm's servervault is its own disaster.
#   2. It survives a change of mount strategy (bind -> separate partition ->
#      whatever comes next) without this file needing to know.
#   3. It is honest about intent: what we require is "the real data is here",
#      and a mount is only today's means of arranging that.
#
# The marker is created during migration and lives on the SSD side, so it is
# only visible through an active mount -- which is exactly the property being
# tested.
#
# See CLAUDE.md "Game data on the SSD" and the NWN block in /etc/fstab.

NWN_VOLUME_MARKER=${NWN_VOLUME_MARKER:-.nwn-volume-id}

# season_require_volume <dir> [label]
#
# Returns 0 if <dir> holds a marker naming <dir> itself; non-zero otherwise,
# after printing a diagnosis to stderr.  Callers exit 78 (EX_CONFIG) so the
# season unit's RestartPreventExitStatus=78 stops the restart loop.
season_require_volume() {
  local dir=$1 label=${2:-directory} marker got want

  # Canonicalise BOTH sides before comparing.  $HOME is /home/james (from
  # /etc/passwd) but /home is a symlink to var/home, so every path derived from
  # $HOME arrives here as /home/james/... while the marker records the resolved
  # /var/home/james/....  Comparing raw strings would fail every single check.
  # This is the same /home-vs-/var/home trap that silently disarms
  # RequiresMountsFor= -- see the mounts.conf.in header.
  want=$(readlink -f "$dir" 2>/dev/null || printf '%s' "$dir")
  marker="$dir/$NWN_VOLUME_MARKER"

  # ONLY enforce for paths /etc/fstab actually declares as a mountpoint.
  #
  # bin/serve is byte-identical across every season repo, but the realms are
  # NOT identically hosted: season 2 and the dev realm live on the SSD, while
  # the season 1 archive was deliberately left on the HDD. It has no bind mount
  # and therefore no marker, so an unconditional check would refuse to start it
  # forever -- turning a safety guard into an outage for the one realm it was
  # never meant to protect.
  #
  # Deriving this from fstab rather than a server.env flag keeps the two in
  # step by construction: the guard enforces exactly where a mount is expected,
  # and if a path is ever de-migrated the guard stands down in the same edit
  # that removes the mount. --mountpoint is an EXACT match, unlike --target,
  # which would walk up and match /var/home for an unmigrated path.
  findmnt --fstab --mountpoint "$want" >/dev/null 2>&1 || return 0

  if [[ ! -f $marker ]]; then
    cat >&2 <<EOF
[season-volumes] FATAL -- refusing to start.

  $label
      $dir
  does not contain the volume marker '$NWN_VOLUME_MARKER'.

  That directory's data lives on /var/mnt/ssd250 and is bind-mounted back here
  by /etc/fstab.  A missing marker means THE BIND MOUNT IS NOT ACTIVE and you
  are looking at an empty directory on the HDD.  Starting here would create a
  server with no servervault, no campaign databases and no module.

  Diagnose:
      findmnt -T "$dir"
      systemctl status var-mnt-ssd250.mount
      journalctl -b -u var-mnt-ssd250.mount
  Repair:
      sudo systemctl start var-mnt-ssd250.mount && sudo mount -a
      findmnt -T "$dir"      # must now show /dev/sdb1
EOF
    return 1
  fi

  got=$(head -n1 "$marker" 2>/dev/null || true)
  if [[ $got != "$want" ]]; then
    cat >&2 <<EOF
[season-volumes] FATAL -- refusing to start.

  $label ($dir) IS mounted, but its marker says the volume belongs at
      $got
  while this path resolves to
      $want

  A bind mount is wired to the WRONG realm's data.  Starting would run this
  season against another season's servervault and campaign databases.
  Check the NWN block in /etc/fstab against the layout it documents.
EOF
    return 1
  fi
  return 0
}

# season_volumes_status <dir> [dir...]
#
# Non-fatal probe for the monitors.  Prints one "ok|missing|wrong<TAB><dir>"
# line per argument and returns non-zero if any is not ok.  Never writes to
# stderr -- bin/watch-all-servers and the roadmap editor's /monitor page both
# render this inline, and a stray diagnostic would corrupt their output.
#
# "Server is running" is a misleading green light if the realm is running
# against an empty directory, which is why the combined monitors surface this.
season_volumes_status() {
  local dir got want rc=0
  for dir in "$@"; do
    want=$(readlink -f "$dir" 2>/dev/null || printf '%s' "$dir")
    # Same fstab-declared rule as season_require_volume: a realm deliberately
    # left on the HDD is "n/a", not a fault, and must not light the monitors up.
    if ! findmnt --fstab --mountpoint "$want" >/dev/null 2>&1; then
      printf 'n/a\t%s\n' "$dir"
    elif [[ ! -f $dir/$NWN_VOLUME_MARKER ]]; then
      printf 'missing\t%s\n' "$dir"; rc=1
    else
      got=$(head -n1 "$dir/$NWN_VOLUME_MARKER" 2>/dev/null || true)
      if [[ $got != "$want" ]]; then
        printf 'wrong\t%s\n' "$dir"; rc=1
      else
        printf 'ok\t%s\n' "$dir"
      fi
    fi
  done
  return $rc
}

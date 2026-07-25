#!/usr/bin/env bash
# Resolve the systemd user unit that runs THIS repo's game server.
#
# Sourced by server-restart, server-stop and empty-restart-handler so none of
# them hard-codes a unit name. Before the season rotation there was exactly one
# server unit, `homers-lotr-server.service`, named by literal in all three — so
# the @-templating in season-cutover-prereqs item 7 would have broken every one
# of them, and a cloned script in a second season repo would have restarted the
# WRONG season's server.
#
# The season instance is this repo's directory name (see systemd/nwn-season-*),
# so a script always drives the season it lives in.
#
# Resolution order:
#   1. nwn-season-server@<repo-dir-name>.service, if THIS instance is configured
#   2. homers-lotr-server.service — the legacy single-instance unit
#
# The fallback is what makes the cutover reversible: the templated units can be
# installed and staged while the legacy unit is still the enabled one, and these
# scripts keep driving whichever is actually in place.
#
# "Configured" is tested by the presence of the instance env file, NOT by
# `systemctl cat`: once the @ template is installed, systemctl happily resolves
# *every* instance name against it, so `cat` succeeds for seasons that were never
# set up and the fallback would never fire. The env file is written per instance
# by bin/season-units.sh --install and is what the unit's EnvironmentFile= needs
# anyway, so its presence is the exact signal.

# season_server_unit [project_root] -> prints the unit name
season_server_unit() {
  local root=${1:-${PROJECT_ROOT:-}}
  [[ -n $root ]] || root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
  local instance
  instance=$(basename "$root")
  if [[ -f "$HOME/.config/nwn-season/$instance.env" ]]; then
    echo "nwn-season-server@$instance.service"
  else
    echo "homers-lotr-server.service"
  fi
}

# season_anvil_dir <run_dir> -> prints the host path of that season's Anvil home
#
# Anvil resolves HomeStorage from the server's -userdirectory, which bin/serve
# bind-mounts as $NWN_RUN_DIR:/nwn/run — so the Anvil home is $NWN_RUN_DIR/anvil
# and PluginData under it is how the host and the plugin exchange control files
# (restart-now, reboot-on-empty, restart-server).
#
# That only works while $NWN_RUN_DIR/anvil is a REAL directory. The Anvil image's
# entrypoint loops over `anvil database hak modules …` and symlinks any entry
# missing from /nwn/run to the container-absolute /nwn/home/<entry>. For every
# other entry that is fine — they dangle on the host by design. For `anvil` it is
# not: the host can no longer traverse it, so arming reboot-on-empty dies in
# mkdir and the empty-restart .path unit watches a path that can never exist,
# which would leave the season shut down instead of restarted.
#
# Season 2 hit exactly that (its run dir was bootstrapped without `anvil`, so the
# entrypoint claimed it). bin/serve now pre-creates the real directory for every
# season; this guard turns the leftover case into a diagnosis instead of a crash.
season_anvil_dir() {
  local run_dir=${1:-${NWN_RUN_DIR:-}}
  if [[ -z $run_dir ]]; then
    echo "season_anvil_dir: no run dir given and NWN_RUN_DIR is unset" >&2
    return 1
  fi
  if [[ -L $run_dir/anvil ]]; then
    cat >&2 <<EOF
[season-anvil] $run_dir/anvil is a symlink to $(readlink "$run_dir/anvil")
               — a container-only path the host cannot write through, so this
               season's reboot-on-empty and empty-restart watcher cannot work.

  Fix (stops and restarts this season's server):
      bin/season-anvil-fix

  Background: season-cutover-guide.md section 5a.
EOF
    return 1
  fi
  echo "$run_dir/anvil"
}

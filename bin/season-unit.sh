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

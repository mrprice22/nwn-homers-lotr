#!/usr/bin/env python3
"""Build gate: the Harvest of Shadows area table is current.

unpacked/hw_areas_inc.nss carries a generated block (area -> pumpkin tier, and
the home location of every Roll of the Fallen boss) written by
bin/gen-halloween-areas.py from the placed creatures and encounters in
unpacked/. Add an area, re-faction a spawn or let the boss registry move, and the
table silently goes stale: a new hostile zone gets decaying town pumpkins, or a
boss's pumpkin ring is planted where the boss no longer lives. Nothing at runtime
would say so.

Fix: python3 bin/gen-halloween-areas.py --write
"""
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.exit(subprocess.call([sys.executable, os.path.join(ROOT, "bin", "gen-halloween-areas.py"), "--check"]))

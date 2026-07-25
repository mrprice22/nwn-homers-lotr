# Reboot Schedule Reference

The daily restart is a two-layer system. Both layers must be changed together whenever you move the schedule.

## How the two layers work

| Layer | What it does | Where configured |
|---|---|---|
| **Anvil plugin** (`ServerRestartManager`) | Broadcasts countdown warnings (60/30/15/10/5/1 min), exports all characters, shuts the NWN server down cleanly | `ANVIL_RESTART_DAILY=HH:MM` in `server.env` |
| **OS timer** (`nwn-reboot.timer`) | Reboots the machine a few minutes after the server shuts down; NWN auto-starts on boot | `/etc/systemd/system/nwn-reboot.timer` — `OnCalendar=` line |

Normal production schedule: **server shuts at 03:00, OS reboots at 03:03**.

---

## enable
sudo systemctl enable --now nwn-reboot.timer

## Changing the OS timer (Linux side)

1. Edit the timer unit file:
   ```bash
   sudo nano /etc/systemd/system/nwn-reboot.timer
   ```
   Change the `OnCalendar=` line, e.g. for a 14:00 test run:
   ```ini
   OnCalendar=*-*-* 14:00:00
   ```

one-line version
  sudo sed -i 's/OnCalendar=.*/OnCalendar=*-*-* 03:01:00/' /etc/systemd/system/nwn-reboot.timer

2. Reload and restart the timer:
   ```bash
   sudo systemctl daemon-reload
   sudo systemctl restart nwn-reboot.timer
   ```

3. Verify the next fire time:
   ```bash
   systemctl list-timers nwn-reboot.timer
   ```
   The `NEXT` column should show the new time.

### Disabling the OS reboot (turning it off)

To stop the daily OS reboot entirely:
```bash
sudo systemctl disable --now nwn-reboot.timer
```
- `disable` removes it from `timers.target`, so it won't arm on future boots.
- `--now` also stops the timer already armed this boot. Plain `disable` (without
  `--now`) leaves the current timer running until the next reboot.

Verify it's off:
```bash
systemctl is-enabled nwn-reboot.timer        # -> disabled
systemctl list-timers --all nwn-reboot.timer # nwn-reboot.timer should not show an active NEXT time
```

Re-enable it later:
```bash
sudo systemctl enable --now nwn-reboot.timer
```

> ⚠️ **This only stops the OS reboot, not the in-game shutdown.** The Anvil
> `ServerRestartManager` still saves characters and shuts the NWN server down at
> `ANVIL_RESTART_DAILY`. The server normally comes back *because the machine
> reboots and the `homers-lotr-server.service` boot service relaunches it* — and
> that service is `Restart=on-failure`, so it will **not** relaunch after a clean
> Anvil shutdown. Net effect: with the OS timer off but Anvil still scheduled,
> the server shuts down at the configured time and **stays down** until you start
> it manually (`systemctl --user start homers-lotr-server`) or reboot.
>
> To turn the daily restart **off completely**, also disable the Anvil side —
> clear `ANVIL_RESTART_DAILY` in `server.env` (see next section) and restart the
> container so no daily in-game shutdown is scheduled.

---

## Changing the NWN-side shutdown (Anvil plugin)

Edit `server.env` — keep the Anvil time **3 minutes before** the OS timer:
```
ANVIL_RESTART_DAILY=13:57   # if OS reboots at 14:00
```

Then restart the NWN container so it picks up the new env var:
```bash
bin/serve stop
bin/serve start
```
(or however you normally restart the server)

---

## Restoring 3 am production schedule

Reverse both changes:
- `server.env`: `ANVIL_RESTART_DAILY=03:00`
- `/etc/systemd/system/nwn-reboot.timer`: `OnCalendar=*-*-* 03:03:00`
- Then `sudo systemctl daemon-reload && sudo systemctl restart nwn-reboot.timer` and restart the container.

---

## Adhoc "reboot on empty" (push an update without kicking players)

For pushing a module update mid-day without waiting for 03:00 or asking players to
log out. Unlike the daily cycle this restarts **only the server service**, not the
whole machine.

**Flow:**
1. Build + deploy the new `.mod` as usual (repack/deploy).
2. Arm it: `bin/reboot-on-empty "Adds the new Moria wing — brief reboot when the server empties."`
   (add `--nwsync` if the update changed haks/tlk clients download).
3. The Anvil `ServerRestartManager` warns online players (broadcast + shout) and
   shows new joiners an on-login notice while armed.
4. Once the server sits empty for ~45s it exports characters, shuts down cleanly,
   and drops an `anvil/PluginData/restart-server` flag.
5. A host `.path` unit (`nwn-season-empty-restart@<instance>.path`) sees the flag and
   runs `bin/empty-restart-handler`: optionally rebuilds NWSync, then restarts that
   season's `nwn-season-server@<instance>.service` — the server comes back on the new
   module. The arm flag is deleted before shutdown, so there is no boot loop.

**Cancel a pending reboot:** `bin/reboot-on-empty off` (players are told it was cancelled).
**Check state:** `bin/reboot-on-empty status`.

**Every season arms independently.** `bin/reboot-on-empty` resolves `NWN_RUN_DIR` from
*its own repo's* `server.env`, and `bin/empty-restart-handler` restarts the unit named
after *its own repo's* directory — so the copy in the season-1 repo drives season 1 and
the copy in the season-2 repo drives season 2. Running one never touches the other.

**Install of the restart trigger units** is part of the season units tool, not a manual
copy:
```bash
bin/season-units.sh --install     # renders nwn-season-empty-restart@<instance>.path
bin/season-units.sh --enable      # enables + starts it (a .path only watches while active)
```
> The `.path` unit watches `$NWN_RUN_DIR/anvil/PluginData/restart-server` — the server's
> *userdirectory* (bind-mounted to `/nwn/run`), which is where Anvil's
> `HomeStorage.PluginData` resolves. This is **not** `NWN_HOME_DIR` (the `/nwn/home`
> mount). `--install` bakes the season's literal run dir into `PathExists=`, because a
> `.path` unit cannot expand environment variables.
>
> **That run dir must contain a *real* `anvil/` directory.** The Anvil image entrypoint
> symlinks `anvil` to the container-only `/nwn/home/anvil` if it is missing, which
> dangles on the host: arming then fails in `mkdir`, and the watcher can never fire — so
> an empty-restart would shut the season down and leave it down. `bin/serve` pre-creates
> it on every start and `--install` refuses to render against a symlinked layout; run
> **`bin/season-anvil-fix`** to repair a season already in that state.

**Requires the Anvil plugin.** `ServerRestartManager` lives inside
`csharp/DungeonSolitaire.Nwn` — a season whose `anvil/Plugins/` is empty
(`Loading 0 DotNET plugin/s` in the log) has neither reboot-on-empty nor the daily
restart, whatever `ANVIL_RESTART_DAILY` says. `bin/reboot-on-empty` warns when the DLL
is missing; `bin/season-anvil-fix` deploys it. See `season-cutover-guide.md` §5b.

**Test without real players:** arm it on an empty server — after the ~45s grace it
will reboot itself (loading whatever `.mod` is currently deployed).

---

## Auto-login after reboot (GDM)

The June 2026 reboot failed because the machine came up at the GDM login screen instead of auto-logging in, so the NWN start-up programs never ran.

Auto-login on Fedora Silverblue/Atomic is controlled by GDM. Check and set it:

```bash
sudo cat /etc/gdm/custom.conf
```

The `[daemon]` section must contain:
```ini
[daemon]
AutomaticLoginEnable=True
AutomaticLogin=james
```

If it is missing or `AutomaticLoginEnable=False`, edit the file:
```bash
sudo nano /etc/gdm/custom.conf
```

**Confirm this is set correctly before the daytime test.** After a successful daytime test cycle confirms auto-login and NWN auto-start are both working, restore the 3 am schedule in both places.

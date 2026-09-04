# Host-level files (installed by hand, as root)

Everything else in `systemd/` is a **user** unit installed by
`bin/season-units.sh`. The files here are different: they are root-owned system
configuration, so nothing in this repo installs them. Copy them by hand, once.

## `coredump-nwn.conf` — keep nwserver cores long enough to be useful

Bazzite vacuums `/var/lib/systemd/coredump` after **5 days**
(`/usr/lib/tmpfiles.d/coredump.conf`), and systemd-coredump's own default
`MaxUse` is a fraction of the disk. Both are sensible defaults for a desktop and
wrong for a game server: a crash gets reported by a player days later, and by
the time anyone looks the core is gone. Nine of the eleven nwserver cores this
host had recorded as of 2026-09-04 were already vacuumed.

`bin/crash-archive` copies the core out into `$NWN_RUN_DIR/crashes/` precisely
so this is not fatal — but it runs once per boot from the backup, so a crash and
a *second* crash-and-vacuum inside one uptime could still lose one. Raising the
retention closes that window.

Install:

```sh
sudo mkdir -p /etc/systemd/coredump.conf.d
sudo cp systemd/host/coredump-nwn.conf /etc/systemd/coredump.conf.d/
sudo systemctl daemon-reload
```

and to stop the 5-day vacuum:

```sh
sudo mkdir -p /etc/tmpfiles.d
printf 'd /var/lib/systemd/coredump 0755 root root 30d\n' \
  | sudo tee /etc/tmpfiles.d/coredump.conf
```

`/etc/tmpfiles.d` overrides `/usr/lib/tmpfiles.d` by filename, so naming it
`coredump.conf` is what makes it win.

**Budget it.** A single nwserver core is ~35-50 MB compressed, and this box has
one spinning disk shared with the live season, NWSync and the backups. 30 days
at the observed crash rate is a few hundred MB; check `du -sh
/var/lib/systemd/coredump` occasionally rather than assuming.

**A core is not shareable.** nwserver's argv carries `-dmpassword` and
`-adminpassword` in plaintext, so both are in process memory and in `ps`. The
core cannot be redacted; `bin/crash-archive` redacts only the metadata, and the
daily backup deliberately excludes `core.zst`.

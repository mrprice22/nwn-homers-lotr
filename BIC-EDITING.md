# Editing player files (`.bic`) and persistent storage — safe procedure

This document describes how we hand-edit player character files and (later) banked
items on the live server, and **where backups are kept** so a player can be restored if
they report a problem. It was first written for the `ab-enhance-stack-bug` fix (collapsing
weapons that carried both an Attack Bonus and an Enhancement Bonus property), and is meant
to be reused for similar bulk repairs.

> **Golden rules**
> 1. **Never edit a logged-in character.** The running server holds them in memory and
>    rewrites the `.bic` on save/logout — your edit will be lost or the file corrupted.
>    Prefer stopping the server; otherwise exclude every live player explicitly.
> 2. **Always back up before writing**, per-file and as a whole-vault archive.
> 3. **Verify semantically, not by byte compare** (see the round-trip caveat below).

## Where the data lives

| Data | Location | Format |
|------|----------|--------|
| Player characters | `~/.local/share/Neverwinter Nights/servervault/<ACCOUNT>/<name>.bic` | GFF (binary) |
| Banked items | `~/.local/share/Neverwinter Nights/database/bankdb.sqlite3`, table `db` (`payload` blob, `compressed` flag) | serialized GFF objects via `SqlBindObject` / `bank_box_inc.nss` |

The server runs as Docker container **`nwnxee-homer`** (image `nwndotnet/anvil`); the
vault and database dirs are bind-mounted into it. Stop/start with
`docker stop nwnxee-homer` / `docker start nwnxee-homer`.

> **Note:** a `.bic` filename is **not** the character's display name. Match characters by
> the in-file `FirstName` field, never by filename (e.g. `mherderer.bic` is the player
> "Mherderer", but `mherderous.bic` is a different character).

## Tooling

`nwn_gff` (from niv/neverwinter.nim) converts GFF ↔ JSON:

```
NWN_GFF=~/.nimble/pkgs2/neverwinter-2.1.2-5952d15f313299678f541b10957ec8c475ed880c/nwn_gff
"$NWN_GFF" -i char.bic -o char.json -k json -p     # bic -> json (pretty)
"$NWN_GFF" -i char.json -l json -o char.bic        # json -> bic
```

**Round-trip caveat:** `gff → json → gff` is **not byte-identical** — `nwn_gff` reorders
the GFF field/label tables — but it is **semantically lossless** (`json → gff → json` is
byte-stable; GFF fields are label-keyed and list/slot order is preserved). The engine
loads a reserialized `.bic` fine. Therefore, **verify a write by re-converting the new file
to JSON and comparing it to the intended JSON**, not by byte-diffing the `.bic`.

## Backups — where they are and how to restore

The `ab-enhance` fixer (`bin/ab-enhance-fix-bic.py --apply`) creates, for every file it
touches:

- A **mirrored backup tree**: `~/nwn-bic-backups/abfix-<UTC>/<ACCOUNT>/<name>.bic`
  (the exact backup root is printed at the end of the run).
- An **alongside copy** next to the original: `<name>.bic.pre-abfix`.

You should also take a **whole-vault archive** before any apply run:

```
tar czf ~/nwn-bic-backups/servervault-<UTC>.tgz \
    -C "$HOME/.local/share/Neverwinter Nights" servervault
```

**Restore one character** (server stopped, or character offline):

```
cp "~/nwn-bic-backups/abfix-<UTC>/<ACCOUNT>/<name>.bic" \
   "$HOME/.local/share/Neverwinter Nights/servervault/<ACCOUNT>/<name>.bic"
# or, quick local restore:
cp "<name>.bic.pre-abfix" "<name>.bic"
```

## Live-player safety in the fixer

`bin/ab-enhance-fix-bic.py`:

- Reads each character's `FirstName` and **skips any `--exclude "Name"`** (repeatable).
- **Aborts** if an exclude name matches no character (catches typos that would otherwise
  leave a live player unprotected).
- Best-effort extra guard: skips a `.bic` currently held open by a process (`lsof`/`fuser`)
  or modified within the last `--recent-min` minutes (default 10).
- Is **dry-run by default**; `--apply` writes. Each write is verified by re-conversion and
  **restored from backup on any mismatch**.
- Is **idempotent**: a re-run finds nothing to change.

## Process checklist (the runbook)

1. **Preferred:** `docker stop nwnxee-homer` so nobody is online (then no `--exclude`
   needed). If running hot, get the current live-player list first.
2. Whole-vault `tar` backup (command above).
3. Dry-run and review the report + `ab-enhance-bic-changes.csv`:
   `python3 bin/ab-enhance-fix-bic.py --exclude <LivePlayer> …`
4. Apply: add `--apply` to the same command.
5. Spot-check: re-run the dry-run (expect 0 changes among non-excluded chars); convert a
   couple edited `.bic` and confirm the weapon shows a single Enhancement Bonus.
6. If stopped, `docker start nwnxee-homer`. Any **excluded** live characters are still
   stale — sweep them once they log off (or stop the server and re-run with no excludes).

## Bank item editing (`bankdb.sqlite3`) — TODO (Phase 3)

Banked weapons are stored as serialized objects in `bankdb.sqlite3` (`db.payload`,
`compressed`) and are **not** covered by the `.bic` fixer. Repairing them requires
deserializing each payload (handle the `compressed` flag and multi-item containers),
applying the same property transform, and reserializing. Back up `bankdb.sqlite3` first.
_This section to be completed when Phase 3 is implemented._

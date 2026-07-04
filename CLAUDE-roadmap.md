# Roadmap & merit-tracking backlog

`roadmap.yaml` (repo root) is the single source of truth for two things at once:

- the **public dev roadmap** at <https://homerslotr.com/manual/Roadmap.html> (what
  shipped, what's in progress, what's planned), and
- the **merit-tracking backlog** — almost every item started as a player suggestion or
  bug report, and when it ships the submitter earns **Merit** to spend on rewards. The
  `player:` field is the credit ledger.

It compiles to `docs.manual/Roadmap.html` via `bin/gen-roadmap.py`, which the wiki build
folds into the published `docs/`.

## The refresh process

```
edit roadmap.yaml                       # by hand, or with the GUI editor (below)
python3 bin/gen-roadmap.py              # -> rewrites docs.manual/Roadmap.html
bin/refresh-homers-lotr-wiki           # -> folds docs.manual/ into published docs/
```

`gen-roadmap.py --check` validates without writing (prints `roadmap.yaml OK` or the
errors). It also joins shipped items to git commit dates (the `commit:` field) and warns
on likely duplicate ideas. The wiki refresh does **not** call `gen-roadmap.py` — run it
yourself first.

## `roadmap.yaml` schema

Top-level keys, in order: `meta`, `groups`, `players`, `redemption`, `housing`, `ideas`.
The GUI editor manages `groups`, `players`, and `ideas`; `meta`/`redemption`/`housing`
stay hand-edited (and are preserved verbatim, comments and all, on every save).

`players` is a flat list of submitter names — the merit ledger's controlled vocabulary.
The GUI's player picker is sourced from it (unioned with any name an idea already uses, so
nothing is ever silently dropped). `community` is the reserved crowd-sourced sentinel.

Each entry under `ideas:` is one backlog item:

| Field | Required | Notes |
|-------|----------|-------|
| `id` | yes | Stable unique key, lowercase-hyphen (e.g. `forge-zero-value-exploit`). Referenced by `dupe_of`. |
| `title` | yes | The public one-line description shown on the page. This **is** the description. |
| `group` | yes | Must match a `groups[].id` (`forge`, `combat-classes`, `bosses`, …). |
| `status` | yes | One of the eight workflow values below. |
| `player` | no | Submitter credit. Omit for admin/community items; use `community` for crowd-sourced. |
| `date` | no | `YYYY-MM-DD`, what the page shows. If absent, derived from `commit`. **When you ship an item, set this to today.** |
| `commit` | no | git commit hash (short or full, e.g. `f1e0b114d7d`) of the change that shipped the item. **Add this when you ship.** Used to derive `date` for shipped items when `date` is absent. |
| `notes` | no | Extra detail beyond the title. May contain **rich-text HTML** (bold/italic/lists/font color, and cross-idea links `<a href="#idea-<id>">`) — authored via the editor's Rich text / HTML tabs, rendered as-is on the public page. |
| `notes_h` | no | Editor-only: remembered pixel height of that idea's Notes box. Written by the GUI when you resize; ignored by `gen-roadmap.py`. |
| `dupe_of` | no | Another item's `id`; merges this submitter's credit into that canonical item. |

**Statuses** (workflow order): `awarded` (shipped, merit awarded) · `implemented`
(shipped, in testing) · `confirmed` (actively being worked) · `wip` (queued, "Up Next") ·
`soon` (one tier deeper) · `later` (further out still) · `planned` (under consideration) ·
`unlikely` (logged but not likely to be implemented).
The badge labels live in `STATUS` in `bin/gen-roadmap.py` — the editor reads them from
there so the two never drift, and the roadmap board orders tiers by their `rank`.

### Agent rules when editing `roadmap.yaml`

These are hard rules — follow them exactly:

- **Shipping an item → `status: implemented`, never `awarded`.** When you finish the code
  for an item, move it to `implemented` (shipped, in testing). **Never** set `awarded` (or
  otherwise mark an item "done") — that step credits Merit to the player and is the admin's
  call. Leave it at `implemented` and let the user promote it manually after they verify
  in-game.
- **Always record the commit hash.** When you ship an item, put the git commit hash of the
  fix in the `commit:` field (short or full, e.g. `commit: f1e0b114d7d`). Commit the code
  first, then write its hash into the item.
- **Always bump `date` to today** (`YYYY-MM-DD`) when you ship an item, so the page reflects
  when it actually shipped — don't leave the original report date.
- **Never invent new ideas on your own. Always ask the user first** before adding a new
  `ideas:` entry. Editing/annotating existing items (status, notes, commit, date) is fine
  without asking; creating a brand-new backlog row is not. When the user does ask for or
  approve a new item, **default `player:` to `HomelessSon (Server Admin)`** unless they name
  a different submitter.
- **Document the fix in `notes`.** Append a short "Fixed YYYY-MM-DD" line (rich HTML is
  fine) describing the root cause and what changed, so the public roadmap and future
  readers have the context. Keep the original report text intact above it.

After editing, validate with `python3 bin/gen-roadmap.py --check`, then regenerate with
`python3 bin/gen-roadmap.py`, and commit `roadmap.yaml` together with the regenerated
`docs.manual/Roadmap.html`.

**Duplicate ideas:** when several players suggest the same thing, keep one canonical item
and add a row per other submitter with `dupe_of: <canonical-id>` and their `player:`.
`gen-roadmap.py` folds all the credits onto the canonical item, and warns (advisory only)
when two same-group titles look similar but aren't linked with `dupe_of`.

**Established submitter names** (avoid typos — a misspelling silently splits a player's
credit). The authoritative list is the `players:` block in `roadmap.yaml` (the GUI sources
its player picker from it); match those strings exactly. As of 2026-06-24:
`dc0960 (Dungeon_Crawler)`, `FLYING HITCHER`, `Fugdish (Try_this)`, `McGondy`,
`-Methonash-`, `Piskan (Alec Cain)`, `Tukwut`, `Yazkir`, `Llikanthus`,
`HomelessSon (Server Admin)`, plus the `community` sentinel. If you add a new submitter,
add them to the `players:` block too.

## GUI editor — `bin/roadmap-editor.py`

A web app (Python stdlib `http.server` + PyYAML, no extra deps) that edits the `ideas`
backlog plus the `groups` and `players` blocks, without the typo classes above. Run it and
open the printed URL:

```
python3 bin/roadmap-editor.py            # serve + open a browser
python3 bin/roadmap-editor.py --serve    # serve only (no browser; used by the service)
python3 bin/roadmap-editor.py --port N   # default port is 8765
python3 bin/roadmap-editor.py --host H   # bind address; default 0.0.0.0 (LAN-reachable)
```

What it does:

- **Typo-proofs the controlled fields.** `group`, `status`, and `dupe_of` are dropdowns
  sourced from the file itself; `player` is a combobox of the managed roster that warns
  (but still allows) when you type a name that isn't already in use.
- **Filter, sort, and hide done.** The list has dropdown filters (status / player /
  group), a sort selector, and a free-text search, all combinable. `awarded` (done) ideas
  are **hidden by default** — tick "Show awarded" to see them.
- **Two views: List / Board.** A toggle switches the right pane between the detail form
  (List) and a **kanban Board** — eight vertical lanes in pipeline order (Under
  consideration → Later → Soon → Up next → In progress → In testing → Merit awarded → Not
  likely). Lane labels come from `gen-roadmap.py`'s `STATUS` so they never drift. The board
  honors the same filters/search; it always shows the awarded lane (ignores "Show
  awarded"). **Drag a card between lanes** — or use its per-card status dropdown — to
  change an idea's `status`, which auto-saves. Click a card to open it in the List form;
  **+ Add idea** works from the board too (it drops you into the form).
- **External-edit / anti-clobber guard.** The page keeps a content hash of `roadmap.yaml`
  as loaded. A background poll warns when the file changes on disk (e.g. an edit by Claude
  or another tab), and every Save/Regenerate/Publish sends that baseline: if the file
  changed since you loaded it, the write is **blocked** with a banner offering **Reload
  latest** (pull the external change, losing in-page edits) or **Force save (overwrite)**.
  A normal save rebases the baseline so the next save doesn't spuriously conflict.
- **Links to the live site.** The header has **Public wiki ↗** (`https://homerslotr.com/`)
  and **Public roadmap ↗** (`https://homerslotr.com/manual/Roadmap`) shortcuts.
- **Manage groups** (button): add a group (`id` + title + order) or rename a title /
  change order. The `id` is the immutable stable key ideas reference, so a title rename
  needs no cascade — every idea shows the new title automatically. A group in use can't be
  dropped (a referencing idea would fail validation).
- **Rich-text Notes.** The Notes field has a **Rich text** tab (toolbar:
  bold/italic/underline, bullet & numbered lists, font color, and a "link to idea"
  picker that inserts `<a href="#idea-<id>">`) and an **HTML** source tab, ServiceNow-
  style. Notes are stored as HTML and render live on the public page (each idea gets an
  `id="idea-<id>"` anchor so the links jump in-page). The box defaults to double height
  and remembers a per-idea height in `notes_h` when you resize it.
- **Manage players** (button): add a name (even before they have an idea) or rename one —
  a rename **cascades** to every idea credited to that name. `community` is reserved.
- **Validates before writing** using `gen-roadmap.py`'s own `validate()` plus structural
  checks (group id format/uniqueness, blank/duplicate player names) — errors block the
  save and are shown inline; nothing is written on error.
- **Preserves the file.** It rewrites only the `groups`/`players`/`ideas` blocks; the
  header comments and the `meta`/`redemption`/`housing` blocks are kept verbatim, and each
  idea's leading section-header comment travels with it by `id`. An unchanged save is a
  byte-for-byte no-op.
- **Save & regenerate** writes `roadmap.yaml` then runs `gen-roadmap.py`, surfacing its
  output (including duplicate-idea warnings) in the page. You still run
  `bin/refresh-homers-lotr-wiki` to publish.

Reordering items in the list reorders them in the file; Add/Delete behave as expected.

**LAN access:** the editor binds `0.0.0.0` by default, so it's reachable from any device
on the local network (`http://<host>:8765/`) — no auth, so trust your network, or pass
`--host 127.0.0.1` to lock it to this machine. On Fedora, open the firewall port if the
phone can't connect: `firewall-cmd --add-port=8765/tcp` (`--permanent` to persist).

### Run it on boot (systemd user service)

`systemd/roadmap-editor.service` keeps the editor always running at
`http://localhost:8765`, so it's just a bookmark instead of a command to remember:

```
mkdir -p ~/.config/systemd/user
ln -s /var/home/james/GIT/nwn_homers_lotr/systemd/roadmap-editor.service ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now roadmap-editor.service
loginctl enable-linger "$USER"      # start at boot, before you log in
```

Check it: `systemctl --user status roadmap-editor.service` and
`curl -s localhost:8765/api/data`.

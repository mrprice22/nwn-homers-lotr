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
| `status` | yes | One of the ten workflow values below. |
| `type` | yes | `Defect`, `Enhancement`, or `Exploit`. Sets the merit value of a shipped item (1 / 2 / 3). |
| `player` | no | Submitter credit. Omit for admin/community items; use `community` for crowd-sourced. |
| `date` | no | `YYYY-MM-DD`, what the page shows. If absent, derived from `commit`. **When you ship an item, set this to today.** |
| `commit` | no | git commit hash (short or full, e.g. `f1e0b114d7d`) of the change that shipped the item. **Add this when you ship.** Used to derive `date` for shipped items when `date` is absent. |
| `notes` | no | **The player-facing release note.** Treat it as a production summary: what changed, from the player's point of view, in a few sentences. May contain **rich-text HTML** (bold/italic/lists/font color, cross-idea links `<a href="#idea-<id>">`, and links to a manual page such as `<a href="QuestGuide.html#gloison">`) — authored via the editor's Rich text / HTML tabs, rendered as-is on the public page. Prefer linking to the Quest Guide or Customizations for detail over spelling it out here. |
| `notes_h` | no | Editor-only: remembered pixel height of that idea's Notes box. Written by the GUI when you resize; ignored by `gen-roadmap.py`. |
| `impl_notes` | no | **Internal — never player-visible.** The builder's record: root cause, scripts and resrefs touched, DB tables, design deviations. Rich-text HTML, same whitelist as `notes`. This is where the technical half of a fix goes. |
| `impl_notes_h` | no | Editor-only: remembered pixel height of the Implementation notes box. |
| `dupe_of` | no | Another item's `id`; merges this submitter's credit into that canonical item. |
| `design_questions` | no | **Internal — never player-visible.** List of `{question, status, answer}`; `status` is `open` or `answered`. See below. |
| `manual_steps` | no | **Internal — never player-visible.** List of `{step, status, blocker}`: toolset work only the admin can do (waypoint placement, loot placement) and UAT scripts. See below. |

**Statuses** (workflow order): `awarded` (shipped, merit awarded) · `implemented`
(shipped, in testing) · `manual` (needs manual finishing — code done, admin toolset work
outstanding) · `design` (needs design input — blocked on an admin decision) · `confirmed`
(actively being worked) · `wip` (queued, "Up Next") · `soon` (one tier deeper) · `later`
(further out still) · `planned` (under consideration) · `unlikely` (logged but not likely
to be implemented).
The badge labels live in `STATUS` in `bin/gen-roadmap.py` — the editor reads them from
there so the two never drift, and the roadmap board orders tiers by their `rank`.

### Pipeline flow

```
planned → later → soon → wip → confirmed → manual → implemented → awarded
                                    ⇅
                                  design
```

`design` branches off `confirmed` and returns to it once every question is answered.
`manual` sits between `confirmed` and `implemented`.

### The internal fields

`notes` is and stays the **player-facing release note**. Nothing else belongs there:

| Content | Field |
|---------|-------|
| What the player will notice, in release-note voice | `notes` |
| Root cause, scripts, resrefs, DB tables, design deviations | `impl_notes` |
| UAT scripts, waypoint/loot placement, admin to-dos | `manual_steps` |
| A call only the admin can make | `design_questions` |

`gen-roadmap.py` renders `notes` and deliberately renders none of the others.

```yaml
  - id: merchant-reputation-gating
    title: "Merchant reputation gating"
    group: economy
    status: design
    type: Enhancement
    notes: "Player-facing release note. See <a href=\"QuestGuide.html#docks\">Quest Guide</a>."
    impl_notes: "merchant_rep_inc.nss; reputation read from repdb, cached per-area."
    design_questions:
      - question: "Should the merchant refuse the quest if reputation < 0, or just charge more?"
        status: open
        answer: null
    manual_steps:
      - step: "Place spawn waypoint at Docks_02"
        status: open        # open | wip | done
        blocker: true       # omit when false
```

**Manual-step states** are `open` → `wip` (started) → `done` (terminal). A step marked
`blocker: true` is one the item genuinely cannot ship without — a missing waypoint that
makes a quest unreachable, say, as opposed to a UAT check. Blockers sort first in the
editor and carry a warning border. Do not write "Blocker:" into `notes` or into the step
text; set the flag.

**Heights.** Every vertically-resizable box in the editor persists its pixel height in the
YAML — `notes_h`, `impl_notes_h`, and per-sub-item `step_h`, `question_h`, `answer_h` —
written only when resized away from the default, and ignored by `gen-roadmap.py`.

**Legacy form.** `manual_steps` was originally a plain list of strings. Those still parse
and are upgraded to `{step, status: open, blocker: false}` on the next save, so no
migration is needed.

The admin answers questions, flips step states and flips statuses; the agent only ever
*adds* questions and steps. Validation (`bin/roadmap-editor.py`,
`validate_internal_fields`) enforces the shapes and two gates:

- `status: design` must carry at least one `open` question — otherwise nothing could ever
  unblock it.
- `status: implemented` / `awarded` must have **no** unfinished blocker step. An item with
  outstanding blocking work belongs in `manual`, which is exactly what that status means.

### Agent rules when editing `roadmap.yaml`

These are hard rules — follow them exactly:

- **Shipping an item → `status: manual` by default, `implemented` only when certain, never
  `awarded`.** When you finish the code for an item, it lands in `manual` (needs manual
  finishing) with the outstanding toolset work listed in `manual_steps`. Set `implemented`
  **only if you can confirm zero manual toolset steps remain** — if you are uncertain,
  choose `manual`. **Never** set `awarded` (or otherwise mark an item "done") — that step
  credits Merit to the player and is the admin's call.
- **Blocked on a design decision → `status: design`.** If an item needs a call only the
  admin can make (mechanics, balance, lore, pricing, UX), set `status: design` and append
  the question(s) to `design_questions` with `status: open` and `answer: null`. **Do not**
  demote the item to `planned`, and **leave all partial work and progress notes intact**.
- **Resuming a `design` item is all-or-nothing.** Only resume implementation once **every**
  entry in that item's `design_questions` has `status: answered`. Never resume partially on
  a subset of answered questions — wait for all of them.
- **Write to the right field.** Player-facing release note → `notes`. Technical record
  (root cause, scripts, resrefs, DB tables, deviations) → `impl_notes`. UAT scripts and
  admin toolset work → `manual_steps`, one step per check, with `blocker: true` only for
  work the item genuinely cannot ship without. **Never** put a UAT script, a resref or a
  "Blocker:" line into `notes`.
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

**The similar-title warning, exactly** (`norm_title()` + the check in `validate()`,
`bin/gen-roadmap.py:109-158`):
- Only compares `title`, and only among ideas that don't already have `dupe_of` set.
- Normalizes each title: lowercase, then collapse any run of non-alphanumeric characters
  (spaces, punctuation, hyphens, quotes, parens) to a single space, then strip.
- Splits the normalized title into a **set of unique words** (order/repeats don't matter).
- Similarity = `len(intersection) / min(len(words_a), len(words_b))` — the fraction of the
  *shorter* title's unique words that also appear in the other title. This is a min-based
  overlap ratio, not `difflib`/edit-distance and not a standard union-based Jaccard index.
- Warns when that ratio is **`>= 0.7`** and the two ideas share the same `group`.
  Cross-group similar titles are never flagged, no matter how close the wording.
- **Advisory only** — printed to stderr, never added to `validate()`'s `errors` list, so it
  never fails `--check` or blocks a GUI save.
- If two ideas are genuinely distinct but trip this warning (e.g. both describe "convert
  X to a roll for bonus damage, or a new Y damage type" for different mechanics X/Y), the
  fix is **not** `dupe_of` — reword one title enough to push the shared-word count below
  the threshold (a synonym swap or rephrase is usually enough) while keeping its meaning.

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
- **Two views: Board / List.** A toggle switches the right pane between the **kanban
  Board** (the default view) and the detail form (List). The board has eight vertical lanes
  in pipeline order (Under consideration → Later → Soon → Up next → In progress → In testing
  → Merit awarded → Not likely); lane labels come from `gen-roadmap.py`'s `STATUS` so they
  never drift. The board honors the same filters/search; it always shows the awarded lane
  (ignores "Show awarded"). **Drag a card between lanes** to change an idea's `status`,
  which auto-saves. An optional **Card status dropdowns (Board)** checkbox (off by default)
  adds a per-card status `<select>` as a drag-free alternative. Click a card to open it in
  the List form; **+ Add idea** works from the board too (it drops you into the form).
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

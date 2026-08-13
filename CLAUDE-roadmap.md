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
python3 bin/publish-roadmap-db.py       # -> refreshes the in-game Recent Updates sign
bin/refresh-homers-lotr-wiki           # -> folds docs.manual/ into published docs/
```

`gen-roadmap.py --check` validates without writing (prints `roadmap.yaml OK` or the
errors). It also joins shipped items to git commit dates (the `commit:` field) and warns
on likely duplicate ideas.

**The daily cycle now does the first three for you.** `bin/refresh-homers-lotr-wiki` runs
`gen-roadmap.py` and `publish-roadmap-db.py` before the wiki build (in that order — the
wiki build is what folds `docs.manual/` into `docs/`), and both are warn-and-continue so a
roadmap.yaml that fails validation can never take the nightly wiki republish down with it.
So an agent that edits `roadmap.yaml` and commits is enough: the public page and the
in-game sign catch up at the next scheduled refresh. Still **don't** run the wiki refresh
as part of an edit — running `gen-roadmap.py` alone remains fine and free.

## `roadmap.yaml` schema

Top-level keys, in order: `meta`, `groups`, `players`, `epics`, `redemption`, `housing`,
`ideas`. The GUI editor manages `groups`, `players`, `epics` and `ideas`;
`meta`/`redemption`/`housing` stay hand-edited (and are preserved verbatim, comments and
all, on every save).

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
| `epic` | no | Id of an entry in the `epics:` block. The item is then published only as one bullet inside that epic's rolled-up card — see **Epics** below. |
| `hidden` | no | `true` = **never published**: kept off the public roadmap page, out of the in-game Recent Updates sign, out of the type/stage pivot counts, and out of any epic's bullet list and `x/y` count. It still shows (chipped and dimmed) in the editor. Omitted entirely when false. |
| `merit_awarded` | no | `true` = the submitter's Merit for this item was really paid into the `meritdb` campaign DB. **Never hand-edit and never set it from an agent** — it is written only by the editor's **Award merit** / **Revoke merit points** buttons, which do the DB write first. It is deliberately separate from `status: awarded` so the status can move back to `implemented` and forward again without paying twice. Omitted entirely when false. |
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

**Unknown fields.** A key outside this table is **preserved** on save (the editor emits it
after the known fields; it used to be dropped in silence — that is how three ideas' retired
`fix:` text would have been lost), and `gen-roadmap.py` prints an advisory
`unrecognised field '<key>'` warning for it. Nothing renders it, though: anything meant for
the page belongs in `notes`, anything meant for the record in `impl_notes`. `IDEA_FIELDS` in
`bin/gen-roadmap.py` is the authoritative set; `FIELD_ORDER` in the editor orders the same
names and warns at startup if the two ever drift apart.

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

### Epics

A big multi-part effort (the quest overhaul, say) ships as dozens of small items, and each
one would otherwise get its own Recently-Shipped card and its own slot on the 10-row in-game
sign. An **epic** collapses them into a single published card:

```yaml
epics:
  - id: quests-overhaul        # stable lowercase-hyphen key, referenced by ideas
    title: "Quest System Overhaul"
    group: quests-areas        # must match a groups[].id — where the card renders
    status: confirmed          # optional; derived when absent
    notes: "Public blurb shown on the card."
```

An epic is **not an idea**: it has no `type`, no `player` and earns no merit — its children
still do, exactly as before. Everything about the rollup is derived:

- **Progress** — `x / y complete`, where `y` is the epic's non-hidden children and `x` those
  with a shipped status (`implemented`/`awarded`). Each child is a bullet: ✔ shipped, ○ not.
- **Date** — the most recently shipped child's date.
- **Status** — the most advanced unfinished child's status (`implemented` once they are all
  done), unless the epic sets `status:` itself.
- **Credit** — the deduped union of the children's `player` credits.
- **Placement** — the epic replaces its children *everywhere* on the public page: one row in
  the Roadmap tables, one card under By Category, and — as soon as any child has shipped —
  one card in Recently Shipped. A partly-finished epic therefore renders twice; only the copy
  matching its own status board carries the `id="epic-<id>"` / `id="idea-<child>"` anchors, so
  in-page links keep working and stay unique.
- **In game** — `sync_recent_updates_db()` emits one `Project: <Title> (x/y complete)` row
  with an ASCII `[x]`/`[ ]` checklist in the detail text, competing with loose ideas for the
  same 10 slots of the sign's *completed* branch. A child with an open `uat` step is
  **pulled out of the rollup** and listed on its own in the *needs testing* branch — a
  progress card is no use to someone trying to reproduce a specific check.

The pivot table at the top of the page still counts the underlying **ideas**, not epics.

### The in-game Recent Updates sign

The Well of Eru sign (placeable tag `recent_updates`, conversation `ru_sign`, scripts
`unpacked/ru_*.nss`) reads the campaign DB **roadmapdb**, table `recent_updates`, written
by `bin/roadmap_publish.py`. Its opening menu offers two lists:

| Branch | Contents |
|--------|----------|
| *Recent updates — completed and tested* | the **10** newest shipped ideas with **no open `uat` step**; epics collapse to one `x/y complete` card. What the sign has always shown. |
| *Updates in testing* | **every** shipped idea that still has an open `uat` step, uncapped and paged 5 at a time. Its detail text appends `What still needs testing:` — the open checks in plain text, each prefixed with its `tester`. |

Rows carry a `bucket` column; the pre-bucket schema is dropped and recreated on the first
publish (every publish rewrites all rows anyway, so nothing is lost). `RU_InitDb()` in
`unpacked/ru_db.nss` carries the same DDL so whichever side runs first wins the same shape.
A schema change here needs a **repack + restart**; the row data does not — the server reads
the campaign DB on each use.

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
        kind: toolset       # toolset | uat | publish | admin
        blocker: true       # omit when false
      - step: "UAT: buy from the merchant at reputation -1 and confirm the refusal line."
        status: open
        kind: uat
        tester: "any character with negative Bree reputation"
```

**Manual-step states** are `open` → `wip` (started) → `done` (terminal). A step marked
`blocker: true` is one the item genuinely cannot ship without — a missing waypoint that
makes a quest unreachable, say, as opposed to a UAT check. Blockers sort first in the
editor and carry a warning border. Do not write "Blocker:" into `notes` or into the step
text; set the flag.

**`kind` is what makes the backlog reportable.** It says which *session* a step belongs
to, so the work can be pulled out by context instead of hunted for item by item:

| kind | what it means | where it surfaces |
|------|---------------|-------------------|
| `toolset` | waypoint placement, palette/blueprint work, appearance, portrait, voiceset, icons | editor → **Toolset Queue** |
| `uat` | in-game verification: log in, spawn it, confirm it reads right | editor → **UAT Queue**, and the in-game sign |
| `publish` | repack / hak build / nwsync / restart | editor → **Toolset Queue** |
| `admin` | everything else (DB seeding, hygiene, out-of-band chores) | — |

Absent means `admin` — the fallback bucket, not a claim the step was triaged. An unknown
value is a **fatal** validation error, because a typo would silently drop the step out of
both queues. The vocabulary lives in `bin/gen-roadmap.py` (`STEP_KINDS`), which the editor
imports, so the two can't drift.

**`tester` is free text on a `uat` step** — `any`, `wizard 43+`, `druid or ranger`,
`level 60 melee`. The UAT Queue groups by it (empty → *Any / unspecified*, sorted last
because it is the triage pile), and it is what a player sees on the in-game board next to
each outstanding check. The editor offers a datalist of values already in use so they stay
consistent; don't invent a fifth spelling of "a high-level caster".

**An open `uat` step is what "not yet validated" means.** `GEN.open_uat_steps(idea)` is the
one predicate behind it, shared by the queues, the sign and the publisher: a shipped idea
with one goes into the in-game board's *needs testing* branch, and out again the moment the
last check is ticked `done`.

**The one-time backfill** is `bin/roadmap-classify-steps.py` (dry-run by default, `--apply`
to write, `--diff` to see the exact change). It tags any step that has no `kind` yet from
the conventional prefixes (`UAT`, `PLACE:`, `PUBLISH:`, `ICON UAT/TUNE`) and a keyword
sweep, so it is safe to re-run after new steps land — it never touches a step you have
already triaged unless you pass `--retag`. It reuses the editor's comment-preserving
writer, and refuses to write if it would *introduce* a validation error (pre-existing ones
are left alone — tagging a step is not the edit that has to fix them).

**Heights.** Every vertically-resizable box in the editor persists its pixel height in the
YAML — `notes_h`, `impl_notes_h`, and per-sub-item `step_h`, `question_h`, `answer_h` —
written only when resized away from the default, and ignored by `gen-roadmap.py`.

**Legacy form.** `manual_steps` was originally a plain list of strings. Those still parse
and are upgraded to `{step, status: open, kind: admin, blocker: false}` on the next save, so no
migration is needed.

The admin answers questions, flips step states and flips statuses; the agent only ever
*adds* questions and steps. Validation (`bin/roadmap-editor.py`,
`validate_internal_fields`) enforces the shapes and two gates:

- `status: design` must carry at least one `open` question — otherwise nothing could ever
  unblock it.
- `status: implemented` / `awarded` must have **no** unfinished blocker step. An item with
  outstanding blocking work belongs in `manual`, which is exactly what that status means.

**Validate every edit with `python3 bin/roadmap-lint.py`.** It imports the editor and calls
the very same `validate_document()` the service's save handler calls, so the rules can't
drift between "what an agent checked" and "what the GUI enforces". Run it after *any* change
to `roadmap.yaml`, before `gen-roadmap.py` and before committing. This matters because
validation is **whole-file**: a single bad item makes the editor refuse *every* save, so an
agent that leaves one `implemented`-with-open-blocker item behind silently locks the admin
out of adding new ideas (this happened — five items, fixed 2026-08-05).

### Agent rules when editing `roadmap.yaml`

These are hard rules — follow them exactly:

- **Shipping an item → `status: manual` by default, `implemented` only when certain, never
  `awarded`.** When you finish the code for an item, it lands in `manual` (needs manual
  finishing) with the outstanding toolset work listed in `manual_steps`. Set `implemented`
  **only if you can confirm zero manual toolset steps remain** — if you are uncertain,
  choose `manual`. **Never** set `awarded` (or otherwise mark an item "done"), and never
  touch `merit_awarded` — that step credits Merit to the player in the live game database
  and is the admin's call, made with the editor's **Award merit** button.
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
- **Always set `kind:` on a step you add**, and `tester:` on a `uat` step whenever you know
  what it takes to run the check ("a wizard past class level 40", "any character with a
  familiar"). An untagged step defaults to `admin` and falls out of both work queues; an
  untagged UAT step lands in the *Any / unspecified* pile the admin then has to triage by
  hand. Both are visible to players on the in-game board, so write the step text so it
  reads as an instruction to someone who has never seen the code.
- **Always record the commit hash.** When you ship an item, put the git commit hash of the
  fix in the `commit:` field (short or full, e.g. `commit: f1e0b114d7d`). Commit the code
  first, then write its hash into the item.
- **Always bump `date` to today** (`YYYY-MM-DD`) when you ship an item, so the page reflects
  when it actually shipped — don't leave the original report date.
- **Never invent new ideas on your own. Always ask the user first** before adding a new
  `ideas:` entry. Editing/annotating existing items (status, notes, commit, date) is fine
  without asking; creating a brand-new backlog row is not. You *may* still **propose**
  decisions or implementations freely — but only **attached to an existing item**, as a
  `design_questions` entry (put your suggested answer in the question text, `status: open`)
  or a `manual_steps`/`impl_notes` note, which queues them for the admin's bulk approval
  without minting a new row. When the user does ask for or approve a new item, **default
  `player:` to `HomelessSon (Server Admin)`** unless they name a different submitter.
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
  which auto-saves. Dragging into the awarded lane (like the Status dropdown) is a **YAML
  edit only** — it never pays Merit; only the form's **Award merit** button does. An optional **Card status dropdowns (Board)** checkbox (off by default)
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
- **Pipeline buttons (and the only thing that pays Merit).** The sticky bar at the top of
  the idea form carries a **back** and a **forward** button, each labelled with the status
  it moves to (`◀ In progress` / `Needs manual finishing ▶` / `Ship · in testing ▶` /
  `Award merit ▶`). They walk the chain
  `planned → later → soon → wip → confirmed → manual → implemented → awarded`; from the
  off-chain `design` and `unlikely`, forward rejoins the chain (`confirmed` / `planned`)
  and back is a dead end. Illegal moves are **greyed with the reason on hover**: unfinished
  blocker `manual_steps`, open `design_questions`, a missing `type`, or an idea that has no
  `id` yet.
  **Forward into `awarded` is the merit payment.** Unlike the Status dropdown or a board
  lane drag — which only edit YAML — this button writes the live `meritdb`: it bumps the
  submitter's counter for the idea's `type` (Defect→`bugs` +1, Enhancement→`features` +2,
  Exploit→`exploits` +3) and appends a `merit_ledger` row reading
  `award: <kind> (roadmap:<idea-id>)`, in one transaction, then re-reads the row to prove
  it landed. If the player can't be resolved or the DB write fails, **the status change is
  rolled back** (every other edit in the form is still saved) and the banner says why.
  An unmatched submitter name opens a picker of `meritdb` accounts; the choice is
  remembered in `roadmap-merit-aliases.json` (gitignored — it holds CD keys) so the same
  roadmap name resolves by itself next time. An idea with no submitter (or `community`)
  asks for confirmation and then moves the status with no payment.
  Once paid, the bar shows a **merit paid** chip and a **Revoke merit points** button
  (confirmation required) that subtracts the points and writes a negative ledger row.
  Moving *back* out of `awarded` never un-pays, and moving forward again never pays twice —
  that is what the `merit_awarded` flag records.
- **Unsaved-changes guard.** The form lives in the DOM until Save, so leaving it used to
  discard edits silently. Clicking another idea, switching to the Board, or adding a new
  idea with unsaved edits now opens a modal: **Save and continue** (navigates only if the
  save actually lands), **Discard and continue**, or **Cancel — stay here**. Closing the
  browser tab warns too.
- **Where the buttons are.** **Save** and **Delete** sit in a sticky bar at the *top* of the
  idea form (the form is long; a bottom Save meant scrolling for every edit). **Save &
  regenerate HTML** and **Publish to Wiki & DB** live in the *left* pane next to **+ Add
  idea**, because they act on the whole file — which also means they now work from the Board
  view, not just the form. **↑/↓ Move** stay at the bottom of the form.
- **Epic + Hidden.** The form has an **Epic** dropdown (next to Type) and a **Hidden**
  checkbox (below Status); the left pane has matching *epic* and *Published / Hidden* filters,
  and hidden or epic-owned rows carry a chip in both the list and the board.
- **Toolset Queue / UAT Queue** (buttons): the hand-off panel shows one idea's steps;
  these show one *kind* of step across the whole backlog — which is what you want when
  you are sitting in the toolset or in the game client rather than in the editor.
  - **Toolset Queue** — every outstanding `toolset` and `publish` step, grouped
    *Toolset* / *Publish & deploy*, blockers first. **Copy as checklist** puts the whole
    view on the clipboard as plain text for a second monitor or a notes file.
  - **UAT Queue** — every outstanding `uat` step, **grouped by `tester`** so you can see
    at a glance what a wizard can clear versus what needs a level-60 melee. *Any /
    unspecified* sorts last and is the triage pile: fill in the tester inline (the input
    is backed by a datalist of values already in use). That field is also what players
    read on the in-game board.
  - Both rows carry the idea's title as a link into the editor form, a `kind` dropdown
    (fix a mis-tagged step in place) and a status dropdown. Changing any of them writes
    `roadmap.yaml` immediately through `POST /api/step-status` — a deliberately narrow
    write that touches exactly one step and **never regenerates or commits**. The step's
    own text is the concurrency token: if it no longer matches, the write is refused with
    "reload before ticking" rather than ticking the wrong row.
- **Manage epics** (button): add an epic (`id` + title + group + optional public blurb),
  retitle/regroup one, or remove one that no idea references. Same modal shape as Manage
  groups; the `id` is the immutable key ideas point at.
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
- **Preserves the file.** It rewrites only the `groups`/`players`/`epics`/`ideas` blocks; the
  header comments and the `meta`/`redemption`/`housing` blocks are kept verbatim, and each
  idea's leading section-header comment travels with it by `id`. An unchanged save is a
  byte-for-byte no-op.
- **Save & regenerate** writes `roadmap.yaml` then runs `gen-roadmap.py`, surfacing its
  output (including duplicate-idea warnings) in the page. **Publish to Wiki & DB**
  additionally body-swaps the page into `docs/manual/Roadmap.html`, refreshes the in-game
  sign DB (`bin/roadmap_publish.py`) and commits + pushes. Neither is required any more
  for the change to reach players — the daily refresh does both — but Publish is how you
  make it land *now*.

  **Publish reaches THIS realm only — the dev realm.** The editor runs in the dev repo
  (`WorkingDirectory` on it), so `docs/` and `roadmapdb` are dev's: the page it pushes
  goes to `dev.homerslotr.com`, and the in-game sign it refreshes is the dev server's.
  Production gets the roadmap when you promote:
  `bin/season-promote.sh --to ../nwn_homers_lotr_s<N> --apply --season <N>` carries
  `roadmap.yaml` across and re-runs `gen-roadmap.py` + `publish-roadmap-db.py` **in the
  target**, which is the only place that can write the live season's `roadmapdb` (it
  lives under that season's own `NWN_HOME_DIR`).

  That is deliberate, not a gap: release notes ship with the release. If you need a
  roadmap-only correction live without promoting a module build, run the publish in the
  target repo directly.

  **Merit is the exception, and it is not one.** Award/Revoke write `meritdb`, which is a
  symlink into `~/.local/share/nwn-shared/` from *every* environment — so merit awarded
  from the dev editor lands in the same ledger production reads, immediately. The editor
  now refuses the write if that symlink is missing (`merit_db_problem()`), because a
  plain file there would accept awards that the next cutover silently discards.

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

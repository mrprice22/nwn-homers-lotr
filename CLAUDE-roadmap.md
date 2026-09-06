# Roadmap & merit-tracking backlog

`roadmap.yaml` (repo root) is the single source of truth for two things at once:

- the **public dev roadmap** at <https://homerslotr.com/manual/Roadmap.html> (what
  shipped, what's in progress, what's planned), and
- the **merit-tracking backlog** — almost every item started as a player suggestion or
  bug report, and when it ships the submitter earns **Merit** to spend on rewards. The
  `player:` field is the credit ledger.

It compiles to `docs.manual/Roadmap.html` via `bin/gen-roadmap.py`, which the wiki build
folds into the published `docs/`.

The same run also writes **`roadmap-credits.json`**, a machine-readable sidecar of who
submitted and who tested each idea. The wiki engine (`nwn_manager`) reads it to put
Bugs / Features / Exploits / Testing columns on the Players index and an "Ideas &
Testing" section on each player page, every row linking back to this page's own
`#idea-<id>` anchor. It exists so the engine never has to parse `roadmap.yaml`: the
status table, the `dupe_of` merge and the `hidden` filter stay here, in one
implementation, and the wiki is handed the already-resolved answer. It is gitignored —
derived data, rebuilt from `roadmap.yaml` on every run.

## The refresh process

```
edit roadmap.yaml                       # by hand, or with the GUI editor (below)
python3 bin/gen-roadmap.py              # -> docs.manual/Roadmap.html + roadmap-credits.json
python3 bin/publish-roadmap-db.py       # -> refreshes the in-game Recent Updates sign
bin/refresh-homers-lotr-wiki           # -> folds docs.manual/ into published docs/
```

`gen-roadmap.py --check` validates without writing (prints `roadmap.yaml OK` or the
errors). It also joins shipped items to git commit dates (the `commit:` field) and warns
on likely duplicate ideas.

**It renders on the dev realm only.** In a repo whose `server.env` says `SEASON_ROLE` is
anything but `dev` it prints a skip line and exits 0 without writing (`--force` overrides).
A season repo's `roadmap.yaml` is only as new as the last promotion, and its git history
does not contain dev's `commit:` hashes, so re-rendering there would replace the page the
roadmap editor publishes with an older, worse one.

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
| `comments` | no | **Internal — never player-visible.** Append-only list of `{author, date, text}`: notes and findings from whoever is looking at the item. `author`/`date` are stamped by the server; there is no route that edits or deletes an entry, which is what makes it safe to hand a `tester`. Nothing renders it — it is not `notes` and never becomes `notes`. |
| `uat_credits` | no | **Internal — never player-visible.** List of `{player, awarded, date}`: the players who helped **validate** this item's fix, each worth **1 merit**. Independent of `player`/`type` — a validator need not be the reporter, and several can be credited on one item. `awarded: true` is the same kind of idempotence flag as `merit_awarded`: **never hand-edit it and never set it from an agent** — it is written only by the editor's per-validator **Award +1** / **Revoke** buttons, which do the `meritdb` write first. Adding a *name* to the list is safe and unpaid; only the button pays. |

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
| What a tester saw when they ran a check | `manual_steps[].result` |
| A finding that fits no particular step | `comments` |

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
        status: open        # open | wip | failed | done
        kind: toolset       # toolset | uat | admin
        blocker: true       # omit when false
      - step: "UAT: buy from the merchant at reputation -1 and confirm the refusal line."
        status: open
        kind: uat
        tester: "any character with negative Bree reputation"
```

**Manual-step states** are `open` → `wip` (started) → `done` (terminal), plus `failed`:
a step that **was run and did not pass** and now needs another code change, not a retry.
`failed` is **editor-only** — the public roadmap page, the in-game Recent Updates sign and
the release notes all decide "outstanding" by testing `status == "done"` and negating it,
so a failed step reads there exactly like any other open step (and still blocks
`implemented`/`awarded` when `blocker: true`). Inside the editor it sorts to the top of the
hand-off panel and of both queues, carries a red left border, and puts a red `failed` chip
on the idea's list row and board card. Setting a step to `failed` **never** rewrites the
idea's own `status` — moving it back to `manual` stays the admin's call. A step marked
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
| `admin` | everything else (DB seeding, hygiene, out-of-band chores) | — |

**There is deliberately no `publish`/deploy kind.** Repack, hak build, NWSync and restart
are implied by every shipped item — the admin knows work has to be deployed before it can
be tested — so a per-item deploy step only added a row to click through. The kind was
removed on 2026-08-26 along with the 31 deploy steps then in the backlog (5 more that were
misfiled under it — a promotion-policy note, a root-cause finding, a toolset-home hygiene
chore, a build-gate check — became `admin`). **Never write a deploy step.** If a deploy is
unusual (hak/TLK rebuild, an NWSync refresh, a client-side download), put that in
`impl_notes`.

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

**The hand-off panel rewrites the whole `manual_steps` list on every save**, from its own
in-page copy (`HO`) — it is not a form bound to the stored step. So a field the panel does
not carry is a field it **deletes**, from every step of every idea the admin opens. That
shipped: `kind` and `tester` were unmodelled for months, so each save re-stamped
`kind: admin` and dropped `tester`, quietly emptying both queues and the "not yet
validated" predicate above. `tests/check_roadmap_step_fields.py` is the gate — it asserts
the page's `HO_OWNED` list covers every key `normalize_step()` can emit, so adding a field
to the serializer without teaching the panel fails the repack. **Add a new step field in
three places at once: `normalize_step()`, `initHandoff()` and `handoffOut()`** — and name
it in the gate's own `PROBE`.
(A new step *state* is a different list: `STEP_STATUS` server-side, plus the page's
`STEP_ORDER` / `STEP_LABEL` / `QSTEP_LABEL` — one ordered constant now feeds both the
hand-off dropdown and the two queue dropdowns, so they cannot drift apart.)
`bin/roadmap-repair-step-kinds.py` restored the values that were already lost by walking
roadmap.yaml's git history for the last non-`admin` `kind` / non-empty `tester` per
(idea id, step text); keep it around in case the class of bug recurs.

**Heights.** Every vertically-resizable box in the editor persists its pixel height in the
YAML — `notes_h`, `impl_notes_h`, and per-sub-item `step_h`, `question_h`, `answer_h` —
written only when resized away from the default, and ignored by `gen-roadmap.py`. The
hand-off panel's default (`HO_DEFAULT_H`) **must equal the textarea `min-height` in the
page CSS**: min-height wins over the inline height, so a smaller default can never equal
the measured `offsetHeight` and every save stamps a spurious `*_h` on every sub-item. That
is where 526 junk `*_h: 64` entries came from; the same gate checks it.

**A no-op save must be a byte-for-byte no-op.** Opening an idea in the list form and
clicking Save with no edits must leave `roadmap.yaml` unchanged — `git diff roadmap.yaml`
empty. It is the cheapest way to catch both of the failures above at once, because both are
invisible in the editor itself and only surface two surfaces away.

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
  touch `merit_awarded` (nor any `uat_credits[].awarded`) — those steps credit Merit
  to a player in the live game database
  and is the admin's call, made with the editor's **Award merit** button.
- **The tester lane belongs to real people, not to agents.** Never write
  `claimed_by`, `result`, `tested_by`, `tested_on` or a `comments` entry — those record
  that a human ran a check or looked at the item, and an agent filling them in makes the
  admin's UAT Review show work nobody did. Write the check itself (a `manual_steps` entry
  with `kind: uat`) and stop there.
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
python3 bin/roadmap-editor.py --host H   # bind address; default 127.0.0.1
```

**It requires a login.** Accounts are created only from a shell on this box
(`bin/roadmap-users.py`) — see [Access control](#access-control) below.

### The workspace shell — navigator + tabs

The page is a **ServiceNow-style workspace**: a **navigator** down the left, and a main
area of **in-app tabs**. It replaced a single 380px left column that carried the external
links, the view toggle, eleven filter controls, sixteen buttons, the who-bar *and* the
scrolling idea list — the list ended up so far down the page that reading it needed
browser zoom.

- **The navigator is links, one per line**, grouped under *Views · Queues · Release notes ·
  Manage · Tools · External*, with a **Filter navigator** box that type-filters them. Drag
  the divider to resize it (clamped 180–560px), or collapse it to a **top strip** with the
  `⏴` button (double-clicking the divider does the same). Width and collapsed state persist
  in `localStorage`. Collapsing does **not** swap in a second copy of the markup — the CSS
  grid restacks the very same `<nav>`, so there is one set of links, one set of `data-cap`
  attributes and one set of handlers however it is displayed.
- **Everything internal opens a tab.** **Board** and **List** are created at boot and cannot
  be closed; everything else — an idea, a queue, the release notes, Duplicates — gets an
  `×` (middle-click closes too). A tab's identity is its key (`board`, `queue-uat`,
  `idea:<id>`), so opening the same thing twice brings the existing tab forward instead of
  duplicating it. The three **External ↗** links are the only anchors that keep
  `target="_blank"`: those are other sites.
- **`#idea-<id>` links work.** Every internal `#…` / `/#…` anchor is caught by one delegated
  click handler and routed to a tab, and `hashchange` plus the boot path read
  `location.hash`. Until this landed **nothing anywhere read that fragment** — there was no
  `hashchange` listener and no `location.hash` read in the whole page — so clicking an idea
  id on the Duplicates view, or an `#idea-…` anchor inside a rich-text `notes` body,
  reloaded `/` and silently landed on the board. `openIdeaLink()` still emits exactly the
  markup it always did, so nothing in `roadmap.yaml` needed migrating. A pasted
  `https://roadmap.homerslotr.com/#idea-<id>` now opens that idea.
- **Panes are detached, not destroyed.** Only the active tab's pane is attached to
  `#panes`; the rest sit detached, held by the tab record. **This is the load-bearing
  decision** — every renderer in the page addresses its widgets by global id through `$()`
  (`#form`, `#f_title`, `#board`, `#q_close`), and two panels alive in the document at once
  would make all of those ambiguous. A detached node is invisible to
  `document.querySelector`, so `$('#f_title')` can only ever match the tab you are looking
  at. Detaching keeps input values and bound handlers, so **unsaved edits in an idea form
  survive switching tabs**; only `scrollTop` is lost, and `activate()` saves and restores
  that by hand. Panel tabs additionally re-render on every activation, so a queue is never
  showing data from whenever you last looked and its buttons are always bound to an
  attached pane.
- **Closing a dirty tab prompts.** `closeTab()` activates the tab first — `isDirty()` can
  only measure the form that is attached, so "close a tab you cannot see" would otherwise
  discard its edits silently.
- **Filters live on the views, not in the navigator.** Filter state is a single `FILTERS`
  object (persisted to `localStorage`, so a reload no longer resets it); the Board and the
  List each render their own bar from it. That is what keeps the two **in sync by
  construction** rather than by copying values between them. The bar's controls are
  addressed by `data-f`, never by id — two live copies could not both carry `#f_fstatus`.
- **History** is the navigator's second mode, ServiceNow's `navigation_history`: the last
  50 things this account opened, newest first, click to reopen, with a **Clear history**
  button. It is stored **server-side** in `auth.sqlite3` (table `navigation_history`, keyed
  on `username`), so it follows the account between browsers and machines rather than
  living in one browser's cache. Revisiting something **moves** it to the top rather than
  adding a row. Reads and writes are `GET`/`POST /api/history` and `POST
  /api/history/clear`, all `view`-capability and all keyed on `self.user.username` — never
  on anything in the request body, so one account can neither read nor pollute another's.
  The POST sits **outside** the `yaml_lock` (with `/api/palette/refresh` and
  `/api/changes/action`): it happens on every click and must never queue behind a
  60-second publish. It is deliberately **absent from `AUDITED`** — "opened the UAT queue"
  in the audit log would bury the writes that log exists for.

What it does:

- **Typo-proofs the controlled fields.** `group`, `status`, and `dupe_of` are dropdowns
  sourced from the file itself; `player` is a combobox of the managed roster that warns
  (but still allows) when you type a name that isn't already in use.
- **Filter, sort, and hide done.** The list has dropdown filters (status / player /
  group), a sort selector, and a free-text search, all combinable. `awarded` (done) ideas
  are **hidden by default** — tick "Show awarded" to see them.
- **Two fixed views: Board / List.** Both are always-open tabs; each carries its own copy
  of the filter bar. The board has eight vertical lanes
  in pipeline order (Under consideration → Later → Soon → Up next → In progress → In testing
  → Merit awarded → Not likely); lane labels come from `gen-roadmap.py`'s `STATUS` so they
  never drift. The board honors the same filters/search; it always shows the awarded lane
  (ignores "Show awarded"). **Drag a card between lanes** to change an idea's `status`,
  which auto-saves. Dragging into the awarded lane (like the Status dropdown) is a **YAML
  edit only** — it never pays Merit; only the form's **Award merit** button does. An optional **Card status dropdowns (Board)** checkbox (off by default)
  adds a per-card status `<select>` as a drag-free alternative (it lives on the board's own
  filter bar now). **Clicking a card opens that idea in its own workspace tab**, as does
  clicking a List row — so you can have several ideas open side by side. **+ Add idea**
  works from anywhere: it opens a tab under the reserved key `idea:__new__` (a brand-new
  idea has no id to be filed under, so it is tracked by object identity), and the tab is
  re-keyed to the real id on its first save.
- **External-edit / anti-clobber guard.** The page keeps a content hash of `roadmap.yaml`
  as loaded. A background poll warns when the file changes on disk (e.g. an edit by Claude
  or another tab), and every Save/Regenerate/Publish sends that baseline: if the file
  changed since you loaded it, the write is **blocked** with a banner offering **Reload
  latest** (pull the external change, losing in-page edits) or **Force save (overwrite)**.
  A normal save rebases the baseline so the next save doesn't spuriously conflict.
- **Links to the live site.** The navigator's **External** section has **Wiki ↗**
  (`https://homerslotr.com/`), **Public roadmap ↗**
  (`https://homerslotr.com/manual/Roadmap`) and **Server monitor ↗** (`/monitor`). These
  are the only links that open a real browser tab.
- **Duplicate review** is a tab (navigator → *Views → Duplicates*), reading the same
  `/api/dupes` + `/api/dupes/action` endpoints, both gated on `edit`. It used to be a
  standalone document at `/dupes` that **nothing in the editor linked to** — reachable only
  by typing the URL. `/dupes` is now a 302 to `/#dupes` so that habit keeps working. Moving
  it in is what lets its per-idea links open an idea tab beside it instead of reloading the
  editor onto the board.
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
  roadmap name resolves by itself next time. That file is **gitignored and not
  regenerable**, so `bin/backup-homers-lotr` captures it (dev realm only, mode 0600,
  staged under `roadmap-editor/` beside the auth DB) — every entry is a human decision
  that nothing else records. The wiki reads the same file, via
  `nwn-wiki --player-aliases`, to credit ideas on player pages; a CD key in it is only
  ever a lookup INTO the roster, never a name out of it, so an alias naming an account
  that has not played this season leaves the idea uncredited rather than printing a key. An idea with no submitter (or `community`)
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
  - **Toolset Queue** — every outstanding `toolset` step, blockers first, then `failed`
    steps. **Copy as checklist** puts the whole view on the clipboard as plain text for a
    second monitor or a notes file.
  - **UAT Queue** — every outstanding `uat` step, **grouped by `tester`** so you can see
    at a glance what a wizard can clear versus what needs a level-60 melee. *Any /
    unspecified* sorts last and is the triage pile: fill in the tester inline (the input
    is backed by a datalist of values already in use). That field is also what players
    read on the in-game board.
    Each UAT row also carries the **claim** half of the tester lane: who holds the
    check, a **Claim**/**Release** button (`POST /api/uat-claim`) and **Report…**,
    which opens the item so the result can be written up. **only mine** filters the
    queue down to the checks this account has claimed — that is what turns a backlog
    into a worklist. For a role with no `edit` these are the *only* controls on the
    row; the status/kind/tester dropdowns need `edit` and are not rendered.
  - **UAT Review** (`merit`) — the other end of that lane: every **unpaid**
    `uat_credits` entry, shown next to the step and the `result` the tester recorded.
    **Award +1** pays it through `/api/uat-award`; **Dismiss** drops the credit and
    keeps the report. Tick *also show credits with no recorded result* to see the ones
    added by hand. See [The `tester` role](#the-tester-role).
  - Both queues carry **two filter checkboxes**, both defaulting to *hidden*: *show done*
    (step-level — a `done` step) and *show awarded ideas* (idea-level — every step of an
    idea whose own `status` is `awarded`, i.e. finished business whose leftover steps would
    otherwise sit in the queue forever). `implemented` and `manual` ideas always show:
    those are the shipped-but-in-testing items the UAT queue exists for. The count line
    says which filters are in force, and **Copy as checklist** reflects them.
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
  output (including duplicate-idea warnings) in the page. It is local and fast: no git, no
  network, nothing published. There is **no preview of the unpublished page** — a `/preview`
  route serving `docs.manual/Roadmap.html` raw was tried and removed, because that file is a
  page fragment dressed as a document (no wiki chrome, no stylesheet at that path, every
  cross-page link 404) and looked broken while telling you nothing the editor's own board
  does not. Publish is cheap and reversible.

- **Publish to Wiki & DB** additionally body-swaps the page into `docs/manual/Roadmap.html`,
  refreshes the in-game sign DB (`bin/roadmap_publish.py`), commits + pushes — **and
  publishes the same page into the LIVE season's repo** (`publish_to_live_realm`), so the
  public roadmap on `homerslotr.com` is current the moment you click it.

  **The page goes live now; the in-game sign still waits for the promote.** That split is
  the whole point:

  | | reaches production when |
  |---|---|
  | public roadmap page (`docs/manual/Roadmap.html` + its `docs.manual/` source) | you click Publish |
  | `roadmap.yaml` itself | `bin/season-promote.sh` |
  | in-game Recent Updates sign (`roadmapdb`) | `bin/season-promote.sh` |
  | player idea credit on the wiki (`roadmap-credits.json`) | you click Publish |

  The credit sidecar travels **with the page**, not with `roadmap.yaml`. It is the other
  half of what a player sees: without it the live wiki renders player pages with no Ideas
  section, so someone who reported a bug can read about it on the roadmap but is credited
  for it nowhere — and that credit is the point of the merit system. The sign is different
  because it announces *shipped code*, which production genuinely is not running yet; a
  credit line is a statement about who asked, which was true the moment they asked.

  `bin/season-promote.sh` also carries the file, as a fallback that seeds a freshly
  promoted season before its first publish.

  A player who reports a bug should see it tracked immediately — that is a *page*, and it
  costs nothing to be honest about early. The sign announces **shipped** work, which is
  only true of production once the module build is promoted, so it rides with the release.

  **The live realm is discovered, never configured.** `live_repo()` scans sibling
  `nwn_homers_lotr*` checkouts for `SEASON_ROLE=live` — the same rule
  `bin/promote-to-prod` uses — so season 3 becomes the target by flipping its
  `SEASON_ROLE`, with no edit here. It refuses when **two** realms are live (a cutover
  overlap: "production" is genuinely ambiguous), when there is no live sibling, and when
  the editor is itself running in the live repo. Every one of those is reported in the
  output pane and **never fails the local publish** — same rule as the DB sync. It also
  warns when `SEASON_LIVE_WIKI_URL` here and `SEASON_WIKI_URL` there disagree about which
  host production is.

  **Only the dev realm renders the page.** `gen-roadmap.py` skips (exit 0, with a skip
  line) on any realm whose `SEASON_ROLE` is not `dev`; `--force` overrides. Two reasons: a
  season repo's `roadmap.yaml` is only as new as the last promotion, and `resolve_dates()`
  reads shipped dates out of **local git** — promotion copies the tree, not the history,
  so dev's `commit:` hashes do not resolve there. Without that guard the live realm's
  nightly `bin/refresh-homers-lotr-wiki` would overwrite every publish with an older,
  worse page.

  **Merit is the exception, and it is not one.** Award/Revoke write `meritdb`, which is a
  symlink into `~/.local/share/nwn-shared/` from *every* environment — so merit awarded
  from the dev editor lands in the same ledger production reads, immediately. The editor
  now refuses the write if that symlink is missing (`merit_db_problem()`), because a
  plain file there would accept awards that the next cutover silently discards.

Reordering items in the list reorders them in the file; Add/Delete behave as expected.

**Access:** the editor binds `127.0.0.1` and requires a login on every request,
including from the LAN. Off-machine access goes through the Cloudflare Tunnel at
<https://roadmap.homerslotr.com>, not an open port — see
[Access control](#access-control).

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
`curl -s -o /dev/null -w '%{http_code}\n' localhost:8765/login` (expect `200`;
`curl localhost:8765/api/data` now answers `401` without a session, which is the
gate working, not a fault).

## Access control

The editor used to bind `0.0.0.0` with no authentication at all, on the theory
that the LAN was the trust boundary. It is now reachable from the internet and
more than one person uses it, so both halves of that theory are gone.

### Roles and capabilities

Roles are a data table in `bin/roadmap_auth.py` (`CAPS` / `ROLES`), not
`if role == "admin"` branches, so adding a role later — a `player` tier that can
only view and submit, say — is a one-line change rather than a sweep through the
request handlers.

| Capability | Covers |
|---|---|
| `view` | the board, roadmap data, merit balances and pending redemptions (read-only) |
| `edit` | saving ideas, ticking `manual_steps` |
| `promote_shipped` | moving an item **into or out of** a shipped status |
| `merit` | awarding/revoking merit and UAT credits — writes the shared `meritdb` |
| `publish` | Save &amp; regenerate, and Publish to Wiki &amp; DB (which git-pushes) |
| `llm_review` | the LLM Changes panel, including approve / reject / reroll |
| `palette` | Palette Finder and its refresh |
| `serverlog` | the `/monitor` page and the realm log tail |
| `merit_view` | reading merit balances and pending redemptions |
| `uat` | claiming a UAT step, recording its result, adding a `comments` note |
| `submit` | creating new ideas (reserved for a future `player` role) |
| `release_notes` | the **Notes · Testers** and **Notes · Players** panels |
| `release_notes_admin` | the **Notes · Admin** panel |

| Role | Has |
|---|---|
| `admin` | everything |
| `dm` | everything **except** `promote_shipped` and `merit` |
| `tester` | **only** `view`, `uat`, `serverlog` and `release_notes` |

So a DM runs the backlog day to day — edits, triage, the queues, the LLM review
panel, and even Publish — but cannot mark anything shipped and cannot pay merit.

### Release notes in the editor

Three sidebar buttons run `bin/gen-release-notes.py` over the commits that are in
the dev realm but not yet promoted to the live season, and show the Markdown it
produces. Same generator as the command line, so what a tester reads here is
byte-identical to what gets published later. See the "Release notes" section of
[CLAUDE.md](CLAUDE.md) for how the join itself works.

| Button | Cap | Shows |
|---|---|---|
| **Notes · Testers** | `release_notes` | shipped-but-unvalidated items, with each open UAT check and who can run it |
| **Notes · Players** | `release_notes` | the same changes as an update announcement |
| **Notes · Admin** | `release_notes_admin` | both, plus `hidden` items, open publish/toolset steps, and the commits no roadmap item claimed |

**Why two capabilities and two routes.** The admin audience is a *different
document*: it carries hidden items and unattributed commits, which is staff
information for the same reason `audit_view` is — so `release_notes_admin` is in
`TESTER_FORBIDDEN`. `ROUTE_CAPS` maps one path to one capability, hence
`/api/release-notes` (testers + players) and `/api/release-notes/admin`.

> **Never add `/api/release-notes` to `PREFIX_ROUTES`.** `route_key()` matches
> `ROUTE_CAPS` exactly before it tries prefixes, so both paths already resolve
> correctly. A prefix entry would collapse `/api/release-notes/admin` onto the
> weaker capability and hand every tester the admin audience. The handler
> *also* rejects `?audience=admin` on the shared path, because the capability is
> carried by the path rather than by the query string.

**Rewrite with local model** re-runs the generator with `--flavor`, which asks the
LAN LLM box to rewrite each note in plain language *and merge duplicate or
related items into one bullet*. The model is chosen from a dropdown listing what
that box is actually serving (`/api/release-notes/models`), so switching off
Gemma is a dropdown change, not a code change; the aliases from
`bin/llm/config.py` are always offered so the picker still works when the box is
asleep. Results are cached per (range, item set, **model**), so a repeat view is
instant and a different model really does produce different text.

### The per-idea environment badge

Every list row and board card carries a colour-coded chip saying which realm that
idea's code is actually in, with a tooltip explaining why. It is **computed, never
stored** — it changes at every promotion with nobody editing anything, so a field
in `roadmap.yaml` would be stale within a day.

| Badge | Means |
|---|---|
| **Live** | every commit is an ancestor of the last promoted sha |
| **Test realm** | every commit is still only in the dev repo |
| **Live · rework on test** | both a promoted and an unpromoted commit — shipped, then a follow-up landed |
| **Reopened after release** | promoted, but the status went back to an unshipped one |
| **Shipped · no commit** | a shipped status with no `commit:` — invisible to the release notes |
| **Tooling (nwn_manager)** | the commit is in the wiki/generator repo, so it has no realm of its own |
| **Commit not found** | resolves in neither repo, **or** exists here but on no branch (amended/rebased away) |

The last two are the triage pair, and the `f_fenv` filter is the worklist: pick
**Commit not found** to get exactly the items whose `commit:` needs fixing. For an
amended commit the tooltip quotes the original subject, which is usually enough to
find the replacement in one look.

**It is shipped as a side map keyed by idea id, never as a key on the ideas
themselves.** `/api/data` hands the browser the raw ideas array and the browser
posts that array straight back on save (`pruneEmpty` copies unknown keys through),
so a computed field hung on an idea would be written into `roadmap.yaml`. The
regression test is: open an idea, save it unchanged, and confirm `roadmap.yaml` is
byte-identical.

### The `tester` role

A trusted player who helps validate fixes. They browse the **whole** backlog
read-only, watch the Server Monitor, claim a UAT check so nobody duplicates it,
record what they saw, and add notes to an item. They do **not** submit ideas —
those still come in through Discord — and they can never pay themselves.

**The thing to understand about this tier: it has no `edit` at all.** That is
the whole security story, and it is deliberately not a "weaker DM". `/api/save`
posts the **entire** `ideas` array and writes what it is given, so any role
holding `edit` can rewrite any field of any item; a per-field filter on that
route would be a large thing to get right and a larger thing to keep right as
the form grows. Instead a tester's only write paths are three narrow endpoints,
each of which patches exactly one step (or appends one comment):

| Route | Cap | What it does |
|---|---|---|
| `/api/uat-claim` | `uat` | Sets or clears `claimed_by` on a `kind: uat` step, and nudges `open → wip`. Refuses a step somebody else holds. |
| `/api/uat-result` | `uat` | Writes the step's `result`, stamps `tested_by`/`tested_on`, sets the status (`wip`/`failed`/`done` only), and adds an **unpaid** `uat_credits` entry. |
| `/api/idea-comment` | `uat` | Appends one `{author, date, text}` to `comments`. Append-only — no edit route, no delete route. |

"UAT fields only" therefore falls out of the route table itself rather than out
of a filter, and `enforce_idea_permissions()` needed no change: a tester never
reaches a document write at all.

**Every player-identifying value is stamped by the server, never posted.**
`claimed_by`, `tested_by`, `uat_credits[].player` and `comments[].author` all
come from the account's `player_name` column — because these names decide who
gets paid merit, and a name off the wire is a name the caller chose. An account
with no `player_name` is **refused** on claim and result (with the CLI line to
fix it) rather than credited to a guess:

```
python3 bin/roadmap-users.py setup                    # interactive; does all of this
python3 bin/roadmap-users.py add bilbo --role tester --player "Bilbo"
python3 bin/roadmap-users.py player bilbo "Bilbo"     # or bind one later
```

**That guard is role-independent, and this is the trap.** `_need_actor()` is on
`/api/uat-claim` and `/api/uat-result` themselves, not on the tester tier — an
**admin** with an empty `player_name` is refused exactly like a tester, and sees
the same "your account has no player name" line under the step. The binding
reads like a tester concern and is not one: it shipped with the tester role, so
the accounts that predate it (the admin's own included) start unbound and cannot
close a UAT step until someone runs the line above. Check `list` after any
account change.

The name must be one `meritdb` (or `roadmap-merit-aliases.json`) resolves, or
the **Award +1** button will not find an account to pay. `setup` proves that
before it writes the binding — it resolves the name through
`roadmap_merit.resolve_with_alias()`, the same function `award_merit()` calls,
and offers to pick the meritdb row and write the alias when it does not match.
That check is the whole reason the wizard exists: an unresolvable binding looks
correct for weeks and fails at the one moment it matters.

**Reviewing and paying.** A recorded result lands an unpaid `uat_credits` row.
The admin's **UAT Review** panel (sidebar, `merit`) lists every unpaid credit
next to what the tester actually reported, with **Award +1** (the existing
`/api/uat-award` — meritdb first, YAML only if that succeeded) and **Dismiss**
(drops the credit, keeps the report). Nothing a tester does can set `awarded`.

**What a tester can still move:** a UAT step's own status, up to `done`. That is
what "complete a UAT task" means, and it does take the item off the in-game
Recent Updates board's "in testing" list — `open_uat_steps()` tests
`status != done` and knows nothing about review. The merit is the reviewed gate,
not the board. Set the step back to `open` if a tester closed one early.

Two smaller notes. A tester reads `impl_notes`, `design_questions`,
`manual_steps` and `uat_credits` on every item — fields this document calls
internal. There is no per-field read filter and seeing the backlog is the point.
And `merit_view` is a **split out of `view`**, not a new power: `/api/merit`,
`/api/meritplayers` and `/api/pending` used to be `view`, which would have shown
a tester every player's balance and pending redemptions.

(Every account needs `player` set as well as a role — see
[The `tester` role](#the-tester-role) above. `list` marks an unbound tester
`(unbound)`; until it is set they can browse and comment but not claim or
report. The same applies to an `admin` or `dm`, where the blank column is
easier to miss.)

**What the DM ceiling does *not* restrict:** `manual_steps`, `design_questions`
and the `uat_credits` list itself stay fully editable on **any** item, including
one already `implemented` or `awarded`. Adding a UAT check to a shipped item is
the DM's core job. The ceiling gates an item's own status, never its subtasks.
(The one thing to know: `implemented` plus an unfinished `blocker: true` step is
a whole-file validation error that blocks saves for *everyone* — see
`bin/roadmap-lint.py`. Adding a plain step to a shipped item is safe; adding a
**blocker** step is the lockout. The validator refuses it loudly rather than
silently, but it is worth knowing before you tick the box.)

### Why route gating alone is not enough

The browser posts the **entire `ideas` array** on every save, and `/api/save`
writes what it is given. Blocking `/api/award` at the route level would
therefore leave `/api/save` as an open back door: a DM could set any item to
`implemented`, or flip `merit_awarded`, without ever calling a merit endpoint.

`roadmap_auth.enforce_idea_permissions()` closes that, and runs on `/api/save`,
`/api/regenerate` and `/api/publish` under the same `yaml_lock` the write takes.
It is deliberately **narrow** — it compares the posted document against disk and
looks at exactly four things: whether an item is in a shipped status, whether a
shipped item still exists, `merit_awarded`, and `awarded` inside `uat_credits`.
Everything else on a shipped item passes through untouched.

The narrow `uat` routes are the counter-example that proves the rule: because
they patch one step rather than accepting a document, route gating **is** enough
for them, and that is exactly why the `tester` role could be added without
extending the field-level check at all.

`ROUTE_CAPS` in `bin/roadmap-editor.py` **fails closed**: a path missing from the
table is denied, so adding an endpoint without deciding who may call it breaks
loudly instead of shipping open.

The browser page hides controls the role cannot use (`CAN()` /
`applyCapabilities()`), but that is a courtesy. The server enforces every rule
independently; never treat the page's gating as the control.

### Managing accounts

Only from a shell on this box — there is no signup page, no password reset and
no in-browser user admin, because a management UI on an internet-facing surface
is a much bigger thing to get right than a script that runs here.

**Use `setup` to create an account.** It prompts through the whole thing — pick
the in-game player from `roadmap.yaml`'s own `players:` roster (each row
annotated with how meritdb resolves it and which login already holds it), prove
the merit link, choose the login name and role, generate or type a password. Run
it on a username that already exists and it becomes a **rebind**: it sets the
player name, optionally the role and password, and leaves everything else alone.
The flag-driven commands below stay for scripting and for one-field changes.

```
python3 bin/roadmap-users.py setup                  # interactive: create or rebind
python3 bin/roadmap-users.py setup --role tester    # skip the role prompt
python3 bin/roadmap-users.py add jane --role dm --name "Jane (DM)"
python3 bin/roadmap-users.py add bilbo --role tester --player "Bilbo"
python3 bin/roadmap-users.py player bilbo "Bilbo"   # bind/rebind the game name
python3 bin/roadmap-users.py list          # accounts, roles, player names, last login
python3 bin/roadmap-users.py roles         # the capability table above
python3 bin/roadmap-users.py passwd jane   # also revokes their sessions
python3 bin/roadmap-users.py role jane admin
python3 bin/roadmap-users.py disable jane  # lock out and log out
python3 bin/roadmap-users.py sessions      # who is currently signed in
python3 bin/roadmap-users.py logout jane   # or --all
python3 bin/roadmap-users.py audit --limit 40
```

Passwords are never taken from the command line (that would put them in shell
history and in `ps`): the commands prompt, or take `--stdin`, or mint one with
`--random`.

Everything lands in an append-only audit log — logins, failures, throttling,
every roadmap write with the ids it changed, and every refusal (`denied.route`,
`denied.field`). Read it with `roadmap-users.py audit`, or in the editor's
**Recent changes** panel.

**A write also records what moved inside each idea.** Every route that reaches
`roadmap.yaml` — save, regenerate, publish, both merit pairs and the queue's
step tick — files a per-field before/after against its audit row in the
`audit_diff` table, down to `manual_steps[2].status`. The capture hangs off
`write_document()` itself rather than off each handler, so a route added later
gets it for free; outside the server (`roadmap-apply-patch.py`, the lint tool)
nothing is armed and nothing is recorded. In the panel, click an idea id in the
**Detail** column to expand the diff in place, with the changed words
highlighted; from a shell it is `roadmap-users.py audit --entry <id>` (the plain
listing marks rows that have one with a `*`).

The audit rows themselves are kept forever — that is the record. The attached
before/after values are bulky (both sides of every `notes` edit) and are pruned
at `DIFF_KEEP_DAYS` (90) days, so an older row still says who changed which
ideas and when, just not what the text used to be. Writes made before this
shipped have no diff at all.

**The account database is a secret.** `~/.local/share/roadmap-editor/auth.sqlite3`
holds password hashes and live session tokens. Same rule as `bin/seed-admindb.sh`:
never commit it, never put it under `unpacked/` (nasher packs that directory
regardless of `.gitignore`), and never send it to the LAN Gemma box.

**It is backed up by the dev realm's daily backup** (`bin/backup-homers-lotr`),
landing at `roadmap-editor/auth.sqlite3` inside the archive. Accounts themselves
are cheap to recreate, but the audit log exists nowhere else — "who changed what,
when" is not reconstructible once it is gone. The Cloudflare token is
deliberately *not* archived; see below.

### Public access — the Cloudflare Tunnel

`https://roadmap.homerslotr.com` is served through a Cloudflare Tunnel:
`bin/serve-roadmap-tunnel` (a rootless podman `cloudflared` container, run by
`systemd/roadmap-tunnel.service`) connects **outbound** to Cloudflare and proxies
requests back down that connection to `127.0.0.1:8765`.

Nothing is forwarded on the router, no inbound port is opened, and TLS
terminates at Cloudflare — which matters because this box is Bazzite
(immutable): nginx and certbot would need `rpm-ostree` layering and a reboot,
and rootless podman cannot bind `:443` while
`net.ipv4.ip_unprivileged_port_start` is 1024.

It is a **remotely-managed (token) tunnel**: the public hostname and the service
it points at (`HTTP 127.0.0.1:8765`) are configured in the Cloudflare dashboard,
and the only thing on this box is the connector token, in
`~/.config/roadmap-editor/tunnel.env` (mode 600). That avoids a
`cloudflared tunnel login` browser dance here and leaves no `config.yml` or
credentials JSON to drift out of step with the dashboard.

**The token is a secret on the same footing as `server.env.local`** — anyone
holding it can serve traffic on your hostname. Never commit it, never send it to
the LAN Gemma box. If it leaks, hit *Refresh token* in the dashboard. The script
passes it via `--env TUNNEL_TOKEN` rather than on the command line, so it does
not show up in `ps` or `podman inspect`.

The one-time setup (create the tunnel, copy the token, add the public hostname)
is documented — not scripted, since it happens in a browser — in the header of
`bin/serve-roadmap-tunnel`.

Because every request arrives from `127.0.0.1`, the real client address comes
from Cloudflare's `CF-Connecting-IP` header — trusted **only** when the socket
peer really is loopback, since a header is otherwise just something a client
typed.

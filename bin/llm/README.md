# `bin/llm/` — the local-LLM harness

A Gemma 4 server on the LAN does this module's bulk prose work: item and creature
descriptions, dialogue proofreading, quest-line design, backlog triage.

The point of the harness is that **running a task costs an agent nothing.** All
the judgement — which items to touch, what context to give, what counts as an
acceptable answer, where it gets written, how much human attention it deserves —
is decided once, in Python, when the task recipe is written. Every run after that
is mechanical.

> Deep background, design rationale and the standing rules live in
> [`CLAUDE-llm-harness.md`](../../CLAUDE-llm-harness.md) at the repo root.
> This file is the orientation map for the directory.

---

## Quick start

```bash
python3 bin/llm/status.py            # is the box up, what is running, what is left
python3 bin/llm/run.py --list        # available tasks
python3 bin/llm/run.py item_desc --limit 20 --dry-run   # always dry-run first
python3 bin/llm/run.py item_desc --apply                # write + record
```

Nothing is written unless you pass `--apply`. Every write lands in the ledger and
is revertible from the roadmap editor's **LLM Changes** panel.

---

## The box

`http://192.168.1.103:11434` — a **Windows** machine contributing GPU inference
over HTTP and nothing else. It has no NWN toolchain and no `module-index/`, which
is why the harness runs *here* and only the inference is remote. That is also
what lets every batch be gated on `tests/smoke-test` before it is committed.

**Never send it secrets.** Unauthenticated plain HTTP on the LAN: no
`server.env`, no CD keys, no `bin/seed-admindb.sh`, no `roadmap-merit-aliases.json`.

| Model | Speed | Use |
|---|---|---|
| `gemma-4-31B` Q4 | 2.2 tok/s | **never for bulk** — 4x slower than 12B for a marginal gain |
| `gemma-4-12B` Q4 | ~8 tok/s | **the default** — ~10s per item at concurrency 4 |
| `gemma-4-E4B` Q8 | ~12 tok/s | fastest, noticeably purpler prose |

Concurrency 4 gives ~2.5x throughput on short generations. On long ones (a quest
outline, ~500 tokens) it buys almost nothing — the box is already saturated by a
single request. There is **no embedding model installed**; `--embeddings` is a
llama.cpp flag that does nothing for Ollama, and the fix is
`ollama pull embeddinggemma`.

---

## Layout

### Core

| File | What it does |
|---|---|
| `config.py` | Box URL, model registry, concurrency, paths. Everything overridable by env var, so the harness can be relocated. |
| `client.py` | Ollama client: `think:false`, JSON schemas, thread pool, disk cache, health probe, `num_ctx`. |
| `gff.py` | Byte-exact reads and writes of GFF-as-JSON fields, including list indices. |
| `wiki.py` | Reads resolved data back out of `docs/` (item properties are numeric in raw GFF). |
| `itemstats.py` | Where each property sits in the module's own distribution. |
| `ledger.py` | The change ledger and its CLI. |
| `fallback.py` | Claude Sonnet as a per-item recovery path. |
| `run.py` | The task runner. |
| `status.py` | What has run, what is running, what is left. |
| `review_api.py` | Server side of the editor's **LLM Changes** panel. |
| `autopilot.py` | The unattended loop (not armed by default). |

### Tasks — `tasks/`

| Task | Writes | Tier |
|---|---|---|
| `item_desc` | `Description` — physical only, no mechanics. What you see *before* identifying. | `auto` |
| `item_desc_id` | `DescIdentified` — may allude to powers, never quantify. What you read *after*. | `auto` |
| `creature_desc` | Creature `Description`, which feeds the Bestiary. | `auto` |
| `dlg_typos` | Proofreads NPC dialogue. Typos and punctuation only, never rewrites. | `review` |

`base.py` is the Task contract; `validators.py` is the quality gate.

**Items are a two-pass pipeline, and the passes have separate prompts.** Run them
in order on any new blueprints:

```bash
python3 bin/llm/run.py item_desc    --apply   # pass 1: unidentified
python3 bin/llm/run.py item_desc_id --apply   # pass 2: identified
```

The selectors chain automatically, so this is safe to re-run at any time and
picks up only what is missing: `item_desc` takes items where **both** fields are
empty, `item_desc_id` takes items where `Description` is filled and
`DescIdentified` is not. Pass 2 is also the only one that gets the item's
`itemstats` power ranking — pass 1 is forbidden from mentioning mechanics at all,
so it has no use for it.

### Standalone tools

| Script | What it does |
|---|---|
| `questlines.py` | Designs the class/prestige questlines from `gemma-questlines/`. Python port of that directory's `run-loop.ps1`, which stays in place. |
| `quest_ideas.py` | Proposes new quest lines and files them as **hidden** roadmap ideas. |
| `roadmap_dupe.py` | Read-only semantic duplicate check for `roadmap.yaml`. |
| `migrate_descriptions.py` | One-off: moved round-one item text into the unidentified slot. |
| `regenerate.py` | Re-runs descriptions written under superseded rules — a wrong power ranking, or a claimed capability the item lacks. Never touches approved text. |

---

## Risk tiers and the ledger

Every generated field write is one JSONL record under `llm-changes/`, committed
alongside the change. Revert is "write `before` back" — precise, independent of
git history, still correct after later commits touch the file.

**The tier is assigned by the task recipe, never by asking a model.** That is
reproducible, free, and keeps the safety decision out of the hands of the thing
being guarded.

| Tier | Meaning |
|---|---|
| `auto` | New text into a previously **empty** field. Nothing human-authored can be destroyed. |
| `review` | **Modifies existing human-written text**, or is player-facing prose. |
| `hold` | Never auto-applied: any `.nss`, any GFF structure, `.git.json` placements, roadmap `status` / `merit_awarded` / `uat_credits`. |

Review in the roadmap editor (`:8765`) → **LLM Changes**. Two modes: *by batch*
audits one run; *by item* puts an item's stat block and both halves of its
description on one row. Or from the shell:

```bash
python3 bin/llm/ledger.py list
python3 bin/llm/ledger.py show <batch> --pending
python3 bin/llm/ledger.py revert <change-id>
```

**An agent's own bulk edits belong in the same ledger** — that is what
`ledger.py record` is for. A change nobody can find is a change nobody can undo.

---

## Re-rolling one description

The panel's `↻ Gemma` / `↻ Sonnet` buttons regenerate a single item in place.

**Raising the temperature does not give you a different answer.** Both item
tasks already run at 0.9, and a re-run returns the identical text in 0.0s
because the disk cache is keyed on the request — the sampler never sees it.
A re-roll needs:

- `client.chat(..., nonce=N)` — changes the cache key *and* becomes Ollama's
  `seed`, so the roll is uncached and differently sampled.
- `Task.item_builder` — rebuilds the prompt for a resref *without* the
  selector's "is this field still empty" filter, which would otherwise exclude
  every item worth re-rolling.
- `Task.field` — the re-roll picks a task by **which field the record targets**,
  not by the record's task name. The newest ledger record for the unidentified
  slot is the *migration* that moved round-one text into it, and
  `desc_to_unidentified` is a relocation script with no prompt: resolving by name
  found nothing and the button just failed.

Re-rolls go to their own `reroll-YYYYMMDD` batch, never appended to the original.

**Which record is "current" is decided by timestamp, not by file order.** Batches
sort newest-first, but records *within* a file keep append order — so two
re-rolls of the same item on the same day land in one file and the **older** one
won. Its text no longer matched disk, so the row was reported as "edited outside
the panel" and lost every one of its buttons, including the ability to approve
text the reviewer wanted to keep. Separate batch files were only half the fix.

### Text with no ledger record

A hand edit, a field written before the harness existed, or a superseded record
leaves text that cannot be approved — approval marks a record, and there is
none. Such rows get a **Keep this** button (`adopt`) that writes a record whose
`before` equals its `after`: an assertion that this text is wanted. Reverting one
is a no-op on disk, which is right — there is no earlier generated version to go
back to. Those rows can still be re-rolled; `reroll` accepts a `file` + `field`
when it has no change id.

Only `item_desc` and `item_desc_id` are re-rollable today — they are the two that
declare `field` and `item_builder`. `creature_desc` and `dlg_typos` would each
need the same split (see below); the button reports that rather than guessing.

## Writing a new task

Copy `tasks/item_desc.py`. Everything decidable without a model is decided
without one — the model supplies prose and nothing else.

| Member | Responsibility | LLM? |
|---|---|---|
| `selector()` | find the work items, and build each one's prompt context | no |
| `system` + `user_template` | the prompt | — |
| `prompt_version` | part of the cache key — **bump it when you edit the prompt** | no |
| `schema` | typed output shape | no |
| `risk` | review tier | no |
| `validate()` | pure-Python post-checks (inherited; override to change them) | no |
| `apply()` | write into the file (inherited) | no |

Optional, but worth setting:

| Member | Why |
|---|---|
| `style_angles` | rotated deterministically per key — the structural fix for monoculture (see below) |
| `field` + `item_builder` | makes the task **re-rollable** from the panel. Split item construction out of `selector()` so a prompt can be rebuilt for a key whose field is already filled |
| `temperature`, `max_chars`, `min_chars`, `allow_digits` | per-task validator tuning |

Rules that came out of building the existing ones:

- **Resolve context from tooling that already resolved it.** Raw GFF is numeric;
  the wiki already renders item properties as text, so `wiki.py` parses that
  rather than adding a second 2DA resolver to keep in sync.
- **Ground it in the module.** `item_index.json`'s `sources` ("Carried by: Orc
  Sorcerer (Morannon)") is what stops the model inventing a provenance.
- **Bump `prompt_version` when you change the prompt** — it is part of the cache key.
- **Exclude what nobody will read.** Filtering to obtainable, named, non-scaffolding
  items cut 2,437 candidates to 944 real ones.
- **Rank the number that means power.** `itemstats` ranks dice by their mean
  (`2d12` = 13, not 2) and `Damage Reduction` by what it soaks, not by the
  enhancement level that bypasses it — and never compares dice against flat
  values in one distribution. Taking the first number in the string got ~16% of
  properties wrong.
- **Do not let the text claim powers the item lacks.**
  `validators.unfounded_claims()` checks assertions against the property list.
  Note it compounds: pass 1 invented stealth from an item's *name*, and pass 2
  inherited that text as context and hardened it.
- **Audit a new task against the ones already fixed before running it.**
  `creature_desc` was written before most of this was learned and would have
  repeated it wholesale: no `style_angles` (monoculture), no `field` /
  `item_builder` (not re-rollable), no rule against inventing abilities, and
  threat bands on **absolute** CR cutoffs that put 39% of every creature in
  "a legendary terror" — the same mistake as ranking items on hardcoded numbers
  instead of the module's own distribution. Percentile bands cut that to 4%.
- **When a task's meaning changes, check its target field.** `item_desc` kept
  writing `DescIdentified` for a while after the two-field split — its prompt was
  always right for the unidentified slot, only `FIELD` was stale, and nothing in
  the build catches that. A fresh blueprint would have got physical-only text in
  the identified slot: exactly the bug the migration existed to undo.

---

## The lesson that keeps repeating

**At scale the failure is sameness, not wrongness.** Every individual output
looks fine; the *set* is a monoculture. It has now happened three times:

- 15 of 16 item descriptions contained the word "heavy".
- Once "heavy" was banned, `wearer` appeared in 11 of 20. Once that was banned,
  `steady` took over at 7 of 20.
- The first three quest proposals were all *speak to the giver → travel → fetch →
  return* — the exact pattern that got 43 shipped quest lines withdrawn in
  August 2026 for being "structurally identical clones with the nouns swapped".

Two things fix it, and **asking the model for variety is not one of them**:

- **Assign structure, don't request it.** `style_angles` on a task and `SHAPES` in
  `quest_ideas.py` rotate deterministically by hashing the item key — stable, so
  the response cache still hits.
- **Detect it at the batch level.** `validators.tics()` and
  `quest_ideas.shape_report()` are the only things that can see a monoculture;
  no per-item review ever will. Check them before any bulk run.

`validators.py` earns its keep the same way — every check there exists because
the failure was *observed*: `stutter()` (a real "strike with strikes"),
`no_typographic()` (curly quotes, while the module legitimately contains *Carn
Dûm* — so non-ASCII in general is **not** rejected), `invented_names()` (against a
Tolkien allowlist, so *Mordor* passes and *"Thandril of Aerthwaite"* does not),
`near_duplicates()`.

---

## The Sonnet fallback

When Gemma fails an item — unparseable JSON after every retry, an empty response,
a context overflow — that item is retried on Claude Sonnet at medium effort
rather than dropped. Round one of `item_desc` lost 29 of 944 that way.

It shells out to the **`claude` CLI**, not the Anthropic SDK: this host has no
`ANTHROPIC_API_KEY`, no `ant`, and no `anthropic` package, while `claude` is on
PATH and authenticated. This repo's only third-party dependency is PyYAML.

```bash
python3 bin/llm/run.py <task> --apply --max-fallback 50   # default
python3 bin/llm/run.py <task> --apply --no-fallback
```

**It spends the user's Claude subscription, not a metered key** — hence the cap.
A systemic Gemma outage must not quietly push a 900-item batch onto it.

**Recovered items are labelled in the panel.** The ledger records
`source: sonnet:medium`, and both panel views show it per row, tinted blue so it
stands out against `gemma:12B`. A batch's group header lists every model that
contributed with counts (`gemma:12B x95, sonnet:medium x2`) rather than naming
the first record's source — which would have reported a batch containing Sonnet
recoveries as pure Gemma.

That labelling matters beyond curiosity: Sonnet's prose is visibly better, so
unlabelled recoveries would quietly raise your impression of what the local model
produces and skew every judgement about whether a prompt needs work.

Ollama enforces structure with its `format` parameter; the CLI has no equivalent,
so `fallback.schema_instruction()` renders the schema into the system prompt. The
first live test without it returned perfectly good prose and no JSON at all.

---

## Long runs

`--apply` writes **in chunks** (`--chunk`, default 50): each chunk is generated,
validated, applied and recorded before the next starts. The first version applied
only at the very end, which meant a 944-item run showed an empty `git status` for
two and a half hours and was indistinguishable from a hang — and a stop at item
940 wrote nothing.

Near-duplicate detection still spans chunk boundaries, so chunking costs nothing
in quality.

`status.py` reads progress for a run started in another terminal from
`.llm-cache/`, scoped to that process's start time, and flags a run whose last
write was over five minutes ago.

---

## Hard rules

- **The local model writes prose and classifies things. It never writes NWScript
  or GFF structure.** It cannot verify that a builtin exists, and a build gate
  will not catch a script that compiles and does nothing.
- **`autopilot.TASKS` is an explicit allowlist.** Adding a recipe to `tasks/`
  does *not* arm it for unattended running.
- **Never `git add -A`.** The wiki refresh and the roadmap editor commit this tree
  on their own schedule; stage only the paths a run touched.
- **New roadmap ideas must be `hidden: true`** — that is what makes generating
  them safe.
- **Filling blank `Comment`/`Comments` fields in `unpacked/` is out of scope by
  decision**, not oversight. Don't add a task for it.

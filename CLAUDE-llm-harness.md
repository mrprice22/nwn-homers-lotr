# The local-LLM harness (`bin/llm/`)

A Gemma 4 server runs on another machine on the LAN. This harness lets it do the
module's **bulk prose work and mechanical triage** so an agent does not have to.

The design goal is that running a task costs an agent **nothing**. All the
thinking — which items to touch, what context to give, what counts as an
acceptable answer, where it gets written, how much human attention it deserves —
is decided once, in Python, when the task recipe is written. Every run
afterwards is mechanical.

## Where things are

| Path | What it is |
|---|---|
| `bin/llm/config.py` | The box's URL, the model registry, concurrency, paths. Every value overridable by env var. |
| `bin/llm/client.py` | Ollama client: `think:false`, JSON schemas, thread pool, disk cache. |
| `bin/llm/gff.py` | Byte-exact reads and writes of GFF-as-JSON fields. |
| `bin/llm/wiki.py` | Reads resolved data back out of `docs/` (item properties). |
| `bin/llm/ledger.py` | The change ledger, and its CLI. |
| `bin/llm/tasks/` | One module per task recipe. **This is where the logic lives.** |
| `bin/llm/run.py` | `python3 bin/llm/run.py <task> [--limit N] [--apply]` |
| `bin/llm/autopilot.py` | The unattended loop. |
| `bin/llm/review_api.py` | Server side of the editor's **LLM Changes** panel. |
| `llm-changes/*.jsonl` | The ledger itself — **tracked in git**. |
| `llm-changes/INBOX.md` | What the autopilot did, newest last. Read this first. |
| `.llm-cache/` | Response cache. Gitignored. Safe to delete. |

## The box

`http://192.168.1.103:11434`, a **Windows** machine (ports 445 and 3389 open, 22
filtered). It contributes GPU inference over HTTP and nothing else: it has no
NWN toolchain, no `module-index/` (that directory is gitignored), and no way to
run the build gates. **The harness therefore runs on this Linux host** and only
the inference is remote. That is also what lets every batch be gated on
`tests/smoke-test` before it is committed.

**Never send secrets to it.** It is unauthenticated plain HTTP on the LAN. No
`server.env`, no CD keys, no `bin/seed-admindb.sh`, no `roadmap-merit-aliases.json`.

Measured on this hardware, 2026-08-23:

| Model | Speed | Use |
|---|---|---|
| `gemma-4-31B` Q4 | 2.2 tok/s | **Never for bulk.** Four times slower than 12B for a marginal gain. |
| `gemma-4-12B` Q4 | ~8 tok/s | **The default.** ~10s per item at concurrency 4. |
| `gemma-4-E4B` Q8 | ~12 tok/s | Fastest, noticeably purpler prose. Bulk and low-stakes only. |

Concurrency **4** gives about 2.5x the aggregate throughput of serial. Higher was
not measured to help. A 944-item batch takes about 2.5 hours.

There is **no embedding model installed**. `--embeddings` is a llama.cpp flag and
does nothing for Ollama; the fix is `ollama pull embeddinggemma`. `client.embed()`
returns `None` until then, and callers fall back.

## Writing a task recipe

A task is six pure-Python members and one prompt (`bin/llm/tasks/base.py`).
Copy `item_desc.py`, which is the fully worked example.

| Member | Responsibility | LLM? |
|---|---|---|
| `selector()` | find the work items | no |
| `context()` | build the prompt input deterministically | no |
| `schema` | typed output shape | no |
| `prompt` | versioned system + user template | — |
| `validate()` | pure-Python post-checks | no |
| `apply()` | write into the file | no |
| `risk` | review tier | no |

Rules that came out of building the first two:

- **Resolve context from tooling that already resolved it.** Raw GFF is numeric —
  `PropertyName: 0, Subtype: 5` — and nothing in `bin/` turns that into text. The
  wiki already does, so `wiki.item_properties()` parses `docs/items/<resref>.html`
  rather than adding a second 2DA resolver to keep in sync.
- **Give the model the item's place in the world.** `item_index.json`'s
  `sources` ("Carried by: Orc Sorcerer (Morannon)") is what stops it inventing a
  provenance, which is otherwise its first instinct.
- **Bump `prompt_version` whenever you change the prompt.** It is part of the
  cache key.
- **Exclude what nobody will read.** The selector filters to items a player can
  actually obtain (`accessible`), that have a name, and whose base item is not a
  creature-slot weapon or a dye kit. That cut 2,437 candidates to 944 real ones.

### Validators earn their keep

`bin/llm/tasks/validators.py` does the quality work a second model call would
otherwise do, for free and reproducibly. Every check there exists because the
failure was **observed**, not imagined:

- `stutter()` — a real generation read *"strike with strikes"*.
- `no_typographic()` — the model emits curly quotes and em dashes; this repo's
  own hand-written descriptions use plain `--`. Note it does **not** reject
  non-ASCII generally: the module legitimately contains *Carn Dûm*.
- `invented_names()` — against a Tolkien allowlist, so *Mordor* passes and
  *"Thandril of Aerthwaite"* does not. Blind spot: a proper noun at the start of
  a sentence is skipped, because otherwise every *"Crafted from..."* is a false
  positive.
- `near_duplicates()` — the failure at 2,000 items is not one bad description, it
  is four hundred interchangeable ones, and each one looks fine on its own.
- `tics()` — the batch-level version of the same problem, and the one that
  actually bit: in the first clean 16-item run, **15 of 16 descriptions contained
  the word "heavy"** and six opened with *"A heavy"*. Nothing else in the
  pipeline could see it. It reports; you fix the prompt.

The structural fix for repetition is `style_angles`: a handful of different
things to notice about an object, rotated deterministically by hashing the item's
resref. Deterministic matters — the response cache still hits on a re-run.

## Risk tiers and the ledger

Every generated field write is one JSONL record under `llm-changes/`, committed
alongside the change. Revert is "write `before` back" — precise, independent of
git history, still correct after later commits touch the file.

**The risk tier is assigned by the task recipe, never by asking a model.** That
is reproducible, free, and keeps the safety decision out of the hands of the
thing being guarded.

| Tier | Meaning |
|---|---|
| `auto` | New text into a previously **empty** field. Nothing human-authored can be destroyed. Applied straight to `unpacked/`. |
| `review` | **Modifies existing human-written text**, or is player-facing prose. Applied, but surfaced for review first. |
| `hold` | Never auto-applied: any `.nss`, any GFF structure, `.git.json` placements, roadmap `status` / `merit_awarded` / `uat_credits`. |

Within a tier the **review-priority score** orders the queue: validator warnings
and near-duplicate score dominate, with the model's self-reported confidence as a
weak tiebreaker.

### Reviewing

The roadmap editor (`:8765`) has an **LLM Changes** panel: grouped by task and
risk, worst first, with **Approve**, **Approve all**, **Edit** and **Revert** per
change. It is served outside the `yaml_lock` because it never touches
`roadmap.yaml`. Or from the shell:

```
python3 bin/llm/ledger.py list
python3 bin/llm/ledger.py show <batch> --pending
python3 bin/llm/ledger.py revert <change-id>
```

**An agent's own bulk content edits belong in the same ledger** — that is what
`ledger.py record` is for. If you change a hundred item descriptions by hand, the
admin should be able to review and revert them the same way.

## Item descriptions: two fields, and relative power

NWN items have **two** description fields and this module uses both — 202 items
already pair a short physical `Description` (shown before identifying) with a
lore-rich `DescIdentified` (shown after). The harness follows that convention:

| Task | Writes | Character |
|---|---|---|
| `item_desc` | `Description` | Physical only. No mechanics, no numbers. What you see before identifying. |
| `item_desc_id` | `DescIdentified` | May **allude** to what the item does, never quantify. What you read after. |

Round one wrote its text into `DescIdentified` before this split existed;
`bin/llm/migrate_descriptions.py` relocated all 915 to `Description`, recording
both writes in the ledger so the move is revertible like anything else. The
`item_desc` task kept pointing at `DescIdentified` for a while after that — the
prompt had always been right for the unidentified slot, only the target field was
stale; it now writes `Description`.

**The two passes chain, so re-running on new blueprints needs no bookkeeping:**

```bash
python3 bin/llm/run.py item_desc    --apply   # pass 1: unidentified
python3 bin/llm/run.py item_desc_id --apply   # pass 2: identified
```

`item_desc` selects items where **both** fields are empty; `item_desc_id` selects
items where `Description` is filled and `DescIdentified` is not. Only pass 2
receives the `itemstats` power ranking — pass 1 may not mention mechanics at all.

### `itemstats.py` — how strong is strong

The thing that made round two worth running. Round one *had* the property list
and was told to ignore it, so an item granting the highest Strength bonus in the
world read exactly like one granting the lowest — the model has no way to know
that +12 is the ceiling here and +1 is the floor.

So every item's properties are parsed into `(property, subtype) → value`,
distributions are built across the whole module, and each value arrives at the
prompt as its percentile *within its own key*:

```
Ability Bonus: Strength +12 -- nothing in the world grants more
Ability Bonus: Strength +1  -- slight
```

**516 distributions, 155 of them rankable.** Four rules, every one found by
running the ranking over real items and disbelieving the output:

- **n ≥ 12 to rank.** `Cast Spell: Harm 1/Day` had n=3, which produced a
  confident "modest" that meant nothing.
- **Only magnitudes get ranked.** For `Cast Spell` the number is *uses per day*,
  not power — the spell name carries the meaning. Rate-shaped values (`/Day`,
  `Unlimited`, `Charges`) are detected by shape and passed through unranked.
- **Rank the number that means power, not the first one.** Two shapes defeat the
  naive read, and between them they covered ~2,400 of 15,000 property instances:
  dice (`2d12` is 13 damage, not 2) and `Damage Reduction: +5 Soak10`, where the
  `+5` is the enhancement bonus needed to *bypass* it and the `10` is what it
  actually stops.
- **Never mix units in one distribution.** 28 keys carry both dice and flat
  values. Compared directly, a flat `5` outranked `2d6`, and `Massive Criticals
  2d12` — the best in the game — landed in the same band as a flat `10`. After
  the fix that `2d12` correctly reads *"nothing in the world grants more"* and
  the flat `10` drops to *"modest"*. The key is `(property, subtype, unit)`.

`VERSION` stamps the cache file, so changing the parsing rules forces a rebuild
rather than silently serving percentiles computed under the old rules.

### Descriptions may not claim powers the item lacks

`validators.unfounded_claims()` compares the text against the property list and
rejects assertions nothing supports — stealth, speed, healing, sight. The case it
was written for: boots granting only `AC Bonus` and `Damage Reduction` whose text
promised the wearer could move *"without alerting the slightest prey"*.

**It compounds across the two passes.** Pass 1 free-associated stealth from the
name *Boots of the Mirkwood Elf* despite having the properties in front of it;
pass 2 was handed pass 1's text as context and hardened the invention into a
firmer claim. Fixing only pass 2 would have left the seed in place.

Both prompts carry the rule and the validator holds the line. Two things learned
tuning it, both encoded:

- **Match claims about the bearer only.** *"breaks the spirit of even the most
  nimble foes"* describes the enemy, not the wearer.
- **Warrants are broader than the obvious property.** Improved Evasion justifies
  "nimble" as well as Dexterity does; a book casting Restoration is a healing
  item. Without those the check flagged correct text — and a validator that cries
  wolf gets ignored, which is worse than not having one.

### Audit a new task before running it

`creature_desc` was written early and would have repeated most of this session's
mistakes across 519 creatures. Auditing it against the fixed tasks found:

| Gap | Consequence |
|---|---|
| no `style_angles` | monoculture across the batch |
| no `field` / `item_builder` | not re-rollable from the panel |
| no rule against inventing abilities | monsters described doing things they cannot |
| threat bands on **absolute** CR cutoffs | 39% of creatures in one band |

That last one is the item-ranking bug in a different costume: hardcoded numbers
instead of the module's own distribution. CR here runs 0.17 to 17,427 with a
median of 88, so `< 150` meant "legendary" covered two fifths of everything.
Percentile bands cut the top band to 4%.

**And the avoid-list has to be measured, not guessed.** Writing the anti-tic rule
from experience, the words chosen were *sickly, jagged, gaunt, hulking, wreathed*.
The first measured run then reported **"heavy" in 11 of 16** — the same word that
hit 15 of 16 on items, and not on the guessed list at all. The rule now names the
measured words. Guessing a model's crutches does not work; `tics()` exists
because measuring them does.

### Regenerating text written under superseded rules

`bin/llm/regenerate.py` re-runs descriptions whose power hint came from the wrong
number (`--mode ranking`), which assert an unfounded capability (`--mode claims`),
or both (`--mode all`).

**Approved text is never regenerated.** Approval is the reviewer saying they want
that text; a correction elsewhere is not licence to overwrite it. Approved items
are excluded and counted separately so nothing goes silently unfixed.

It exists rather than reusing `run.py` because the tasks' selectors deliberately
skip items whose field is written — which is every item here. Selection is by
explicit resref and prompts are rebuilt via `Task.item_builder`.

**A rejected generation is retried once with a nonce.** Without that the reject
is cached, so re-running serves the identical bad text back and the queue never
drains — measured at 4 rejects in 8 on the first corrected-prompt run, rising to
7 of 8 accepted once the retry was added.

Gold value is deliberately secondary and never quantified — only bucketed
(`mundane` … `artifact-tier`). The item with the best negative resistance in the
game is best-in-slot at a middling price, so **overall tier is
`max(best property percentile, gold percentile)`**.

`item_brief()` is used by *both* the prompt builder and the review panel, so what
the model was told and what you see while reviewing cannot drift apart.

### Reviewing them

The **LLM Changes** panel has two modes. *By batch* audits one run; *by item*
puts an item's stat block, its unidentified text and its identified text on one
row, which is the only way to judge whether the register matches the thing.

### Re-rolling one description

The **LLM Changes** panel has `↻ Gemma` and `↻ Sonnet` buttons on every item
description. Each generates a fresh one in place and records it, so a re-roll is
revertible like any other change and re-rolling twice still walks back.

**Temperature is not what makes this work.** `item_desc` and `item_desc_id` were
already at 0.9, and re-running an item still returned the byte-identical text —
in 0.0s, because the disk cache is keyed on the request and the sampler is never
reached. Two things were actually needed:

- **A nonce** (`client.chat(..., nonce=N)`): it changes the cache key *and*
  becomes Ollama's `seed`, so the roll is both uncached and differently sampled.
- **`Task.item_builder`**: the selector deliberately skips items whose field is
  filled, which is by definition every item you would want to re-roll. Item
  construction is now split out of the selector so a prompt can be rebuilt for
  any resref regardless of state.

Re-rolls land in their own dated `reroll-YYYYMMDD` batch rather than being
appended to the original. `read_all()` sorts batches newest-first but keeps
append order *within* a file, so a re-roll written back into its source batch
would sort as though it were older than the text it replaced.

`↻ Sonnet` spends the Claude subscription — one call per click, no cap, because
it is a deliberate human action rather than a batch.

## The Sonnet fallback

When Gemma fails an item — unparseable JSON after every retry, an empty
response, a context overflow — that item is retried on Claude Sonnet at medium
effort rather than dropped. Round one lost 29 of 944 this way.

It shells out to the **`claude` CLI**, not the Anthropic SDK: this host has no
`ANTHROPIC_API_KEY`, no `ant`, and no `anthropic` package, while `claude` is on
PATH and authenticated. Adding an SDK and a provisioned key to serve a rare
recovery path is a poor trade against a repo whose only dependency is PyYAML.

```
python3 bin/llm/run.py <task> --apply --max-fallback 50
python3 bin/llm/run.py <task> --apply --no-fallback
```

Two things that are easy to get wrong:

- **The schema must be stated in words.** Ollama enforces structure with its
  `format` parameter, so task prompts never had to ask for JSON. The CLI has no
  equivalent — the first live test returned perfectly good prose and no JSON at
  all. `fallback.schema_instruction()` renders the schema into the system prompt.
- **This spends the user's Claude subscription, not a metered key.** Hence
  `--max-fallback` (default 50): a systemic Gemma outage must not quietly push a
  900-item batch onto it. The ledger records `source: sonnet:medium` so the panel
  shows which items did not come from the local model.

## Watching a run

```
python3 bin/llm/status.py            # box, in-flight runs, per-task backlog, ledger
python3 bin/llm/status.py --watch    # refresh until you stop it
python3 bin/llm/status.py --quick    # skip the per-task counts (they read every blueprint)
```

`run.py --apply` writes **in chunks** (`--chunk`, default 50): each chunk is
generated, validated, applied and recorded before the next starts. The first
version applied only at the very end, which meant a 944-item run showed an empty
`git status` for two and a half hours and was indistinguishable from a hang. It
also meant a stop at item 940 wrote nothing.

Near-duplicate detection still spans chunk boundaries — `mark_duplicates()` takes
the text of every earlier chunk — so chunking costs nothing in quality.

Progress for a run started in another terminal is read from `.llm-cache/`, which
is the one place a running batch leaves a trace per item rather than per chunk.
`status.py` flags a run whose last cache write was over five minutes ago.

## Roadmap triage

`bin/llm/roadmap_dupe.py` is a **read-only** semantic duplicate check for
`roadmap.yaml`. It supplements — does not replace — the word-overlap warning in
`gen-roadmap.py`, which compares normalised titles at 0.7 overlap within a group.
That catches *"Add bank to Bree"* against *"Add a bank in Bree"* and misses the
duplicates people actually file, because two players describing the same wish
rarely pick the same nouns. Demonstrated: *"let players dye their armour colours"*
matches the existing `dye-kit` (*"Requesting proper dying kit..."*), which shares
almost no words with it.

```
python3 bin/llm/roadmap_dupe.py --id <idea-id>
python3 bin/llm/roadmap_dupe.py --title "..." --group forge   # before filing
python3 bin/llm/roadmap_dupe.py --all                          # needs embeddings
```

It prints candidates and stops. **Setting `dupe_of` stays a human decision**,
because merging two players' ideas also merges who gets the merit credit.

## Quest line proposals

`bin/llm/quest_ideas.py` proposes new quest lines and files them as roadmap
ideas with **`hidden: true`**.

```
python3 bin/llm/quest_ideas.py --count 5
python3 bin/llm/quest_ideas.py --count 5 --apply
python3 bin/llm/quest_ideas.py --theme "Dwarves of Erebor" --count 3
```

It is the odd one out in this harness: the output is a **design proposal in
prose**, not a field in a blueprint. It writes no NWScript, no journal entry, no
area and no blueprint — the local model cannot check that a script function
exists or that an area is reachable, and an unchecked idea belongs on the
backlog, not in the module.

`hidden` is what makes generating them safe: the entry is off the public roadmap
page and off the in-game Recent Updates sign, so a bad proposal costs one click
to delete. Filed as `group: quests-areas`, `status: later`,
`player: HomelessSon (Server Admin)`.

### The sameness problem, which is the real one

On **2026-08-14 the admin withdrew 43 shipped quest-line items** with the
complaint that they were *"structurally identical clones of each other -- every
class line is `oath -> fetch shard -> reforge` with the nouns swapped"*
(`~/.claude/plans/review-roadmap-for-ideas-humming-bee.md`).

Asked for quest lines with no further steering, this model reproduces that exact
failure. The first three proposals it ever made were all *speak to the giver,
travel, pick the thing up, bring it back* -- with a pack, some crates and a herb
in the object slot. Each one reads fine on its own. **The set is the rejected
pattern.**

This is the same shape of problem as `validators.tics()` finding "heavy" in 15 of
16 item descriptions, and it takes the same two-part fix:

- **`SHAPES`** — eight quest structures (investigation, a choice with a cost, a
  defence, somebody is lying, a rivalry, a rescue that goes wrong, a
  negotiation, an aftermath). One is **assigned** per proposal, sampled without
  replacement. Fetch-and-return is deliberately not on the list. Assigning beats
  asking: a prompt that merely requests variety gets three fetch quests.
- **`shape_report()`** — the batch-level detector. Flags a run that is still ≥50%
  fetch-and-return, that opens or ends ≥50% of its quests with the same two
  words, or where every proposal has an identical step count. Run against the
  original three it reports all three symptoms.

If you change that prompt, check `shape_report()` output before filing anything.
A per-proposal review will not catch a monoculture — that is exactly how
forty-three of them shipped.

### Grounding

Grounding is stricter here than anywhere else, because a quest that references a
place which does not exist is worse than no quest. The prompt gets a sample of
the module's real area names, its real journal quests and the quest ideas already
on the backlog; every proposal is then checked against those, and one naming an
area that does not exist is flagged and not filed. Consecutive areas are also
checked for reachability through `area_graph.json` (`MAX_HOPS`, 12): a quest is a
journey a player actually makes, and two steps twelve loading screens apart is
not the quest the model thought it was writing. Note this is the module's own
topology, not Tolkien's map — Rivendell to Ithilien is 4 transitions here, so it
passes, correctly. New ideas are appended
through the editor's own `serialize_ideas` under its `yaml_lock` — the same path
`bin/roadmap-apply-patch.py` uses — because `apply-patch` itself only patches
existing ids and refuses to create.

## Class questlines

`bin/llm/questlines.py` designs the class and prestige questlines, one quest at a
time, against the backlogs in `bin/llm/gemma-questlines/`.

```
python3 bin/llm/questlines.py --list          # progress across all 21 lines
python3 bin/llm/questlines.py --once          # one quest, then stop
python3 bin/llm/questlines.py --only fighter
python3 bin/llm/questlines.py                 # work every backlog to the end
```

It is a Python port of `gemma-questlines/run-loop.ps1`, which **stays in place
unchanged**. The design is the PowerShell script's and is preserved exactly --
same backlog files, same checkbox ticking, same output and synopsis formats. What
changed is only the plumbing:

- **Reaches the box over the network** (`config.OLLAMA_URL`) instead of
  `localhost`. The .ps1 assumed it was running *on* the Windows machine.
- **Takes its model from the shared registry.** The .ps1 defaulted to
  `gemma4:12b-it-qat`, which is not installed there — only the three
  `hf.co/unsloth/gemma-4-*` builds are — so that default could only ever fail.
- **Goes through `llm/client.py`**, so it inherits the disk cache, retries, the
  health probe and `status.py` visibility.
- **Runs classes in parallel.** Quests *within* a line must stay sequential —
  each is prompted with a synopsis of the ones before it — but the 21 lines are
  independent, so they run concurrently.

  **Do not expect much from that.** Measured: 82s per quest serial, 74s per
  quest at concurrency 3 — about 1.1x, not 3x. Roughly 4 hours for the 187
  outstanding either way. Item descriptions parallelise 2.5x because each call
  generates ~65 tokens and is dominated by queueing and prompt overhead; a quest
  generates ~500 and is GPU-bound, so the box is already saturated by one
  request. Concurrency here mainly buys resilience — one slow line does not
  block the rest.

- **Asks for `num_ctx: 8192`**, as the .ps1 did. The box loads this model at
  4096, and a line's prompt grows as it runs: every finished quest appends a
  synopsis line to "STORY SO FAR". On overflow Ollama truncates from the *front*
  — the design brief — so the output format, the reward tiers and the
  do-not-repeat-yourself rule would silently vanish, worst on the late capstone
  quests, and the result would still read like a perfectly good quest. The first
  port of this dropped the setting; restoring it is what makes the long lines
  trustworthy.

File formats are written back **exactly as found**, BOM and CRLF included.
Normalising them would be a one-line change and a bad one: PowerShell 5.1's
`Get-Content` misreads BOM-less UTF-8, so stripping the BOM would corrupt any
non-ASCII in the backlogs the next time the .ps1 ran.

A response missing any required section (`**Hook:**`, `**Setting:**`,
`**Objectives:**`, `**Rewards:**`, `SYNOPSIS:`) is rejected and the box is **not**
ticked, so a bad generation is retried rather than silently banked. A line that
fails stops rather than continuing — the synopsis chain is what the next quest in
that line is built on.

Output is markdown design documents under `gemma-questlines/output/`, not module
content: no ledger entry, no build gate, `git diff` is the review path. Nothing
here writes to `unpacked/`, and nothing here is a quest the module can run.

### Known gap: the brief does not know it is NWN

`prompts/design-brief.md` describes the world and the output format but never
says which ruleset the rewards must fit. So the model reaches for tabletop 5e
vocabulary that has no meaning in this module — generated rewards so far mention
*"survival checks"*, *"Athletics"*, *"once per long rest"* and *"action
economy"*, none of which exist in NWN (the skills are Discipline, Spot, Search,
Listen and the rest; rests are not long rests).

These are design outlines for a human to build from, so it is a translation cost
rather than a broken deliverable — but it is worth fixing in the brief, not in
the plumbing. A short "mechanics vocabulary" section naming the real NWN skills,
feat types and item property families would remove it.

## The autopilot

```
python3 bin/llm/autopilot.py --once --dry-run    # what it would do
python3 bin/llm/autopilot.py --once              # one batch, committed
systemctl --user enable --now llm-autopilot.timer
```

Not enabled by default: it commits and pushes to `main`, so arming it is a
decision. One cycle is pick task → generate 60 → validate → apply what passes →
`tests/smoke-test` → commit → push → append to `INBOX.md`. **If the gates fail the
whole batch is reverted and nothing is committed.**

The scope fence is in `autopilot.TASKS`, an explicit allowlist. Adding a task to
`bin/llm/tasks/` does **not** arm it.

**Out of scope by decision, not oversight:** filling blank `Comment` / `Comments`
fields on anything in `unpacked/` — area builder notes and the like. They are
notes to builders, not content, and a generated one restates what the area
already shows. Do not add a task for them.

**Why the fence exists:** this model cannot check whether an NWScript function
exists, and inventing plausible-looking builtins is its characteristic failure.
A build gate would not catch a script that compiles and does nothing. So it
writes prose and classifies things, and that is all.

It is also not the only writer of this tree — the wiki refresh and the roadmap
editor both commit on their own schedule. Hence: an advisory lock, `git add`
with named paths only (never `-A`), and a rebase before pushing.

# Gotchas — silent failure modes and common traps

- **NWScript is windows-1252: a UTF-8 em dash in a `.nss` reaches the player as
  garbage.** NWN reads script text one byte per character, so the `—` in
  `"Your account — 10 most recent tests"` arrived on the Hall of Champions sign
  as `Your account â€" 10 most recent tests`. In a comment the same bytes are a
  compile trap instead. It is invisible in a diff and it is a recurring slip in
  machine-written scripts (811 characters across 401 files when this was first
  swept). **Write ASCII in `.nss` — dashes, straight quotes, `...`, `->`.**
  `python3 bin/ascii-clean-nss.py --apply` sweeps the tree and
  `tests/check_ascii_nss.py` fails the repack on a new one. **This does not
  extend to raw high bytes**, which are how NWN colour tags are written
  (`COLOR_RED` is `"<c\xfe\x20\x20>"` — those bytes are the colour, not text);
  both tools work on a list of UTF-8 typographic sequences and skip anything
  inside a `<cRGB>` tag, deliberately. Generators that emit `.nss`
  (`bin/gen-*.py`) must emit ASCII too, or the gate fails the next time they run.
  GFF JSON is unaffected: `nwn_gff` converts it with a declared encoding.

- **`CreateItemOnObject`'s stack argument is clamped to the base item's
  `Stacking` value — asking for six of a non-stackable item silently gives
  exactly one.** No error, no log line, no compile warning: the script *looks*
  like it hands out six and hands out one. `slot_token` (the Rune of Expansion)
  is `BaseItem 24` = `miscsmall`, whose `hak_2da/baseitems.2da` `Stacking` is
  **1**, so `CreateItemOnObject("slot_token", oPC, 6)` in `welloferuenter.nss`
  gave testers a single rune, and the cheat chest's `..., 3)` gave one — both
  went unnoticed until a tester counted. Most quest items, keys and tokens are
  `miscsmall`/`misclarge` and behave the same way; arrows/bolts/bullets (20/21/25,
  `Stacking 999`), potions (`10`) and gold do stack, so the argument is only
  meaningful there. **Rule: before passing a count, check `Stacking` for that
  base item in `hak_2da/baseitems.2da`; when it is 1, loop and create one at a
  time.** Stackable items merge on their own, so the loop is always correct —
  it is only slower. When *counting* what someone already holds, sum
  `GetItemStackSize` over the inventory rather than using
  `GetItemPossessedBy` (which finds a stack of six and reports "has one",
  and matches on **tag**, not resref).

- **A symlink in `database/` must resolve *inside the container*, not just on
  the host.** The server runs in podman with only two bind mounts,
  `$NWN_RUN_DIR:/nwn/run` and `$NWN_HOME_DIR:/nwn/home`. An absolute symlink
  pointing anywhere else — e.g. the cross-season shared `meritdb`/`admindb` in
  `~/.local/share/nwn-shared/` — resolves perfectly from a host shell and
  **dangles inside the container**. Every host-side check passes (`ls -l` shows
  a good link, `sqlite3` reads the tables, the backup works) and the only
  symptom is nwserver aborting at module load with
  `terminate called … what(): database unavailable` and systemd restart-looping
  it. `bin/serve` mounts `$NWN_SHARED_DIR` at its own host path so absolute
  links resolve identically on both sides; anything else you link into
  `database/` needs the same treatment.

- **Wrong-shape `.git` instances fail silently.** If a struct in a
  `Creature List` / `Placeable List` / etc. has the wrong `__struct_id`
  (e.g. you copied the `.utc`/`.utp` blueprint root instead of an existing
  sibling instance), or uses the wrong position-field names for its list
  (`XPosition` on a placeable, `X` on a creature), the engine skips it
  with no error and no log line. Symptom is "the NPC isn't there." Always
  start a new instance by copying a neighbor in the same list. See the
  canonical-id table in [CLAUDE-blueprints.md](CLAUDE-blueprints.md).

- **ResRefs are limited to 16 characters.** The NWN engine (and nasher) enforce
  a hard 16-character limit on all resource names — filenames without extension,
  `TemplateResRef`, `Tag` (when used as a resref), and `Conversation` fields.
  Exceeding it causes a pack-time error. Name new blueprints with this in mind;
  abbreviate rather than truncate: e.g. `mw_aurel_armor` not `mw_aurelius_armor`.

- **ResRef collisions are silent.** Two blueprints of the same type with
  the same `TemplateResRef` are an error you'll see at pack time;
  *across* types you can have e.g. an item and a creature both named
  `foo` (they live in different namespaces). Stick to unique resrefs to
  keep your sanity.

- **Duplicate blueprints sharing a `Tag` are legal and silent.** Nothing
  fails: not the repack, not `check_divergent_creatures.py` (it only compares a
  placement against *its own* blueprint), not `check_palette_coverage.py`. The
  only symptoms are two identical-looking leaves in the toolset palette and an
  orphan half that drifts out of date. 126 tags in this module are shared by
  more than one blueprint, and `bin/split-divergent-creatures.py` manufactures
  them by design. **Before adding another, check
  `module-index/unspawned_creatures.json`** for an orphan that should be reused
  or deleted instead — and prefer a second *instance* of the existing blueprint
  (see "Place an existing NPC in another area" in
  [CLAUDE-recipes.md](CLAUDE-recipes.md)).

- **`.git` and `.gic` are positional.** They share an instance ordering;
  reordering one without the other breaks comments. When deleting an
  instance, delete from both at the same index.

- **Dialogue `Index` fields are positional.** Removing an entry
  re-indexes the list. Easier to leave orphans than to renumber.

- **`Cost` on items is a `dword`.** Don't set it to a negative value.

- **`Conversation` field is a `resref`, not a tag.** Easy to confuse;
  it's the dialogue's filename, lowercase, ≤ 16 chars.

- **CEP HAKs are a hard dependency.** Most appearance IDs above ~600,
  most placeable models, and many item types come from the CEP HAK pack
  listed in `Mod_HakList`. Renaming or removing those breaks the module.

- **The custom TLK is `cep`.** Any `cexolocstring` `id` lookup resolves
  via `cep.tlk`. New IDs would require modifying the TLK; for new
  content, prefer inline strings (`{"0": "..."}`) and skip the TLK
  altogether.

- **Don't commit `dist/` or `*.ncs`.** `.gitignore` covers these but be
  watchful when adding files.

- **Path handling.** `unpack.sh` symlinks the source `.mod` to
  `/tmp/homers_lotr_v3.mod` because `nwn_erf` chokes on apostrophes in
  paths. The module file in NWN's data dir is literally
  `Homer's LOTR VEL v3.mod`.

- **The `.ptm` plot manager file is legacy.** It's a binary blob from
  the old plot wizard; effectively empty in this module. Leave it alone.

- **Scripts can fail silently in-game** — a missing or uncompiled
  `Mod_OnHeartbeat` script just means no heartbeat code runs, with no
  in-game error. Always check for compile errors at repack time and
  test the affected event in a fresh module load.

- **GIC `__struct_id` must be 4, not the loop index.** Programmatic GIC
  appends using a loop counter as struct_id (0, 1, 2, …) cause the NWN
  toolset to crash with an access violation when opening the area.
  Always hardcode `__struct_id: 4` for every creature GIC entry.

- **`<c…>` colour tags in dialogue text render as `<UNRECOGNIZED TOKEN>`.** The
  dialogue engine resolves `<…>` as token references before colour processing, so
  raw `<cÿÿ >` tags become unknown tokens. The fix is to put the colour string in a
  custom token via `SetCustomToken` (in `onmoduleload.nss`) and reference it as
  `<CUSTOM6100>text<CUSTOM6102>` in the dialogue JSON. See the Colour tokens section
  in [CLAUDE-nwscript.md](CLAUDE-nwscript.md) for the full pattern and the reserved
  token number table.

- **Same-type attack/damage bonuses DO NOT STACK — never apply one directly.** The
  engine applies the **highest** bonus of a type and discards the rest, so an
  `EffectAttackIncrease` outside the ledger doesn't merely fail to stack: it
  *suppresses* every smaller bonus for as long as it lasts. Legendary Prowess's
  permanent +5 silently swallowed Bard Song entirely, and made the attack half of
  Legendary Grip worth exactly zero. Register the amount with
  `BPool_Set()` (`unpacked/bonus_pool_inc.nss`) instead — the ledger sums the live
  entries and applies one effect built from the total. `tests/check_bonus_pool.py`
  is the build gate; exemptions live in its table and must state a reason.
  Related: `EffectDamageIncrease` takes a **`DAMAGE_BONUS_*` constant, not a flat
  int** (raw 7 = 1d6, raw 10 = 2d6), which is how Legendary Reaping's top stacks
  became dice — the ledger converts once, on the total.

- **Don't invent NWScript builtins.** A fabricated identifier in a
  heavily-included header produces one `UNDEFINED IDENTIFIER` error per
  consumer script. Verify every engine function in the Lexicon
  (<https://nwnlexicon.com>) or by grepping existing `unpacked/*.nss`.
  See [CLAUDE-nwscript.md](CLAUDE-nwscript.md) for known non-existent functions.

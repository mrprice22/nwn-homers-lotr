# Gotchas — silent failure modes and common traps

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

- **Don't invent NWScript builtins.** A fabricated identifier in a
  heavily-included header produces one `UNDEFINED IDENTIFIER` error per
  consumer script. Verify every engine function in the Lexicon
  (<https://nwnlexicon.com>) or by grepping existing `unpacked/*.nss`.
  See [CLAUDE-nwscript.md](CLAUDE-nwscript.md) for known non-existent functions.

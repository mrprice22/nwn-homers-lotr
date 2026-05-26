# GFF-as-JSON format and module.ifo.json

## GFF-as-JSON format

`nwn_gff` round-trips between binary GFF and a typed JSON shape. Every leaf
value is wrapped in `{"type": "<gff-type>", "value": ...}`:

```jsonc
{
  "__data_type": "UTC ",                          // top-level resource type tag
  "Tag":          { "type": "cexostring", "value": "MyNPC" },
  "Str":          { "type": "byte",       "value": 14 },
  "HitPoints":    { "type": "short",      "value": 25 },
  "ChallengeRating": { "type": "float",   "value": 1.0 },
  "TemplateResRef":  { "type": "resref",  "value": "myresref" },
  "FirstName":    { "type": "cexolocstring",
                    "value": { "0": "Aragorn" } },     // 0 = English string
  "Description":  { "type": "cexolocstring",
                    "value": { "id": 12677 } },        // TLK ref, looks up cep.tlk
  "ClassList":    { "type": "list",                    // lists hold structs
                    "value": [
                      { "__struct_id": 2,
                        "Class":      { "type": "int",   "value": 12 },
                        "ClassLevel": { "type": "short", "value": 1  } }
                    ] }
}
```

### Key conventions

- **`__data_type`** — 4-char resource tag at the root: `"UTC "`, `"UTI "`,
  `"UTD "`, `"UTP "`, `"UTW "`, `"UTM "`, `"UTT "`, `"UTE "`, `"ARE "`,
  `"GIT "`, `"GIC "`, `"DLG "`, `"JRL "`, `"FAC "`, `"IFO "`, `"ITP "`. The
  trailing space is significant.
- **`__struct_id`** — appears on every struct inside a list. Sometimes used by
  the engine as a tag (e.g. inventory slots in `Equip_ItemList`: 8 = right
  hand, 16 = left hand, 2048 = creature hide). Don't invent new struct IDs
  unless you know what they mean — copy from a similar entry.
- **GFF primitive types** — `byte` (u8), `char` (i8), `word` (u16),
  `short` (i16), `dword` (u32), `int` (i32), `dword64`, `int64`, `float`,
  `double`, `cexostring` (UTF-8 string), `cexolocstring`, `resref`, `list`,
  `struct`, `void` (binary blob, base64-encoded).
- **`resref`** — max **16 characters**, lowercase, used as the in-game
  filename. Must be unique per resource type. Filenames must match:
  `myresref.utc.json` → `TemplateResRef: myresref`.
- **`Tag` / `cexostring`** — up to 32 characters. Tags identify *instances*
  at runtime via `GetObjectByTag`; multiple instances can share a tag. Tags
  are case-sensitive in script lookups.
- **`cexolocstring`** — keys in `value` are language IDs:
  `0`=EN, `1`=FR, `2`=DE, `3`=IT, `4`=ES, `5`=PL, `6`=KO, `7`=zh-CN.
  An `"id"` key is a **StrRef** into `cep.tlk`. If both are present, the
  inline string wins. For new content, use `{"0": "English text"}` only.
- **Empty `cexolocstring`** is `{ "type": "cexolocstring", "value": {} }`.
- Field-key order in JSON does not matter; `nwn_gff` sorts keys
  case-insensitively on output.

## Module config — `module.ifo.json`

The single most important file. Holds the area list, every module-level
event hook, HAK list, custom TLK reference, entry point, etc.

### Module event hooks (current wiring)

| Field             | Script             | Notes                                |
|-------------------|--------------------|--------------------------------------|
| `Mod_OnHeartbeat` | `bleeding`         | Custom bleed-out / death-at-negative |
| `Mod_OnModLoad`   | `onmoduleload`     | PC autosave init + MW NPC spawn      |
| `Mod_OnClientEntr`| `hgll_cliententer` | Letoscript apply on enter (HGLL)     |
| `Mod_OnClientLeav`| `hgll_client_exit` |                                      |
| `Mod_OnAcquirItem`| `acquireditem_tag` | Hooks into Bedlamson Dynamic Merchants |
| `Mod_OnUnAqreItem`| `deathamuletdecay` | "deathamulet" cleanup                |
| `Mod_OnActvtItem` | `dmfi_activate`    | DM Friendly Initiative item          |
| `Mod_OnPlrDeath`  | `ondeath020`       |                                      |
| `Mod_OnPlrDying`  | `mod_dying`        |                                      |
| `Mod_OnPlrLvlUp`  | `mod_level`        |                                      |
| `Mod_OnPlrRest`   | `on_mod_rest`      |                                      |
| `Mod_OnSpawnBtnDn`| `mod_respawn`      | Player respawn-button handler        |

Available but unused: `Mod_OnModStart`, `Mod_OnPlrEqItm`,
`Mod_OnPlrUnEqItm`, `Mod_OnCutsnAbort`, `Mod_OnUsrDefined`.

### Other module fields worth knowing

- `Mod_Entry_Area` = `thewelloferu` (entry point: `Mod_Entry_X/Y/Z` and
  `Mod_Entry_Dir_X/Y`).
- `Mod_HakList` = the eight CEP 2 HAKs. Custom haks would go here.
- `Mod_CustomTlk` = `cep`. Numeric `id` in any cexolocstring resolves
  against `cep.tlk` via NWN's TLK lookup.
- `Mod_XPScale` = `150` (1.5×).
- `Mod_StartHour` / `Mod_DawnHour` / `Mod_DuskHour` / `Mod_MinPerHour` —
  in-game time config.
- `Mod_Area_list` — list of every area's ResRef. **Adding or removing an
  area requires updating this list.** The engine uses it to enumerate areas
  on load.
- `Mod_CacheNSSList` — scripts the engine should pre-cache. Most additions
  don't need this; only specific event/include scripts that benefit from
  early load are listed here.

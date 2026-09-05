# Graffiti the Well of Eru — merit reward 301, end to end

Merit reward **301** ("Graffiti the Well of Eru with your name & description",
5 merit, `needs_dm = 1`) lets a player leave a permanent placeable in the Well of
Eru. It used to be a bare `pending` row whose only text was its own catalogue
label, so the DM who had to place the thing had no idea *what* the player wanted.
This is the machinery that closes that gap: buy the reward, get sent to the Well,
choose any placeable look in the game on a live easel, name it, then tell
Barliman — and the choice lands on the redemption row as the admin-facing note.

The DM still places the final placeable by hand in the toolset. What changed is
that the request is now unambiguous.

## The pedestal and the canvas — why there are two objects

NWScript has **no `SetPlaceableAppearance`**, and
`NWNX_Object_SetAppearance` (`unpacked/nwnx_object.nss:122`) carries the note
*"will not update for PCs until they re-enter the area."* So the only way to show
a change live is to **destroy the placeable and create a new one** with the new
look — which would end any conversation that object was hosting.

Hence two objects, and this is the thing to remember before "simplifying" it:

| object | tag | role |
|---|---|---|
| pedestal | `graf_pedestal` | what you **talk to**. Permanent. `Conversation = graf_conv`, `OnUsed = graf_use`. |
| canvas | `graf_canvas` | what **changes**. Created and destroyed by `Graf_Render` on every pick. Not useable, no conversation. |

`Graf_Render` sets the appearance **in the same script frame as the
`CreateObject`**, so a client's first sight of the object already carries the
chosen look. If that ever proves flaky for players standing in the area, the
fallback is `CreateObject` → `NWNX_Object_SetAppearance` → `CopyObject` →
destroy the original; the copy is broadcast with the new appearance.

The canvas stands 2 m in front of the pedestal, computed from the pedestal's own
position and facing, so moving the pedestal in the toolset moves the canvas with
it. Place a waypoint tagged **`wp_graffiti_canvas`** to pin it somewhere else
instead.

Placed in `thewelloferu` at (55.08, 85.11). The teleport arrival point is the
separate waypoint **`wp_placeablecustomizer`** (55.04, 74.99), beside the second
`merit_keeper` instance.

## The catalogue — two campaign DBs

| DB | written by | holds |
|---|---|---|
| `placeappdb` | **the host**, `bin/publish-placeable-db.py` | read-only reference: ~9,500 placeable appearances, in 289 categories, in 9 themes (`appearances` / `categories` / `themes`). Never written from game. |
| `graffitidb` | the module | per-CD-key picks (`picks`) and the easel's claim / last-rendered state (`easel`). Per-season. |

NWScript cannot read a 2DA and 9,500 rows cannot live in a `.nss`, so the
catalogue goes where the Recent Updates sign's data goes — a campaign DB the
module queries at runtime.

```
python3 bin/gen-placeable-appearances.py    # -> module-index/placeable_appearances.json
python3 bin/publish-placeable-db.py         # -> <NWN_HOME_DIR>/database/placeappdb.sqlite3
```

`gen-placeable-appearances.py` reads `placeables.2da` through `nwn_resman_cat`,
using the module's **own** hak list (`unpacked/module.ifo.json` → `Mod_HakList`).

> **Hak priority is inverted between NWN and resman.** NWN gives the *first* hak
> in the module list priority; resman's `--erfs` gives the *last* one. The
> generator reverses the list before handing it over. Get this backwards and you
> silently index `cep2da.hak`'s 2,307-row table instead of `cep2_top_2_71.hak`'s
> 10,448-row one — with no error, just a much smaller menu.

CEP encodes the category in the Label itself (`"Crystal: Floating, Red*
(Schazzwozzer)"`). Base BioWare rows have no prefix and are bucketed on the
leading word (`"Crate 01"` → `Crate`), which merges them into the CEP category of
the same name; buckets that would hold one row are folded into `Misc`. Dropped:
`[Deprecated]*`, `VFX`, and anything invisible. Result today: **9,554 appearances
in 289 categories**.

### Themes — why there is a level above the categories

289 categories is **33 pages** of paging before the player sees a single model,
so the generator groups them into **nine themes** — nine because that is exactly
one page of the in-game menu, which makes the browser's first level a single
screen:

| theme | categories | appearances |
|---|---:|---:|
| Nature & Water | 56 | 1460 |
| Building & Terrain | 50 | 2525 |
| Furniture & Home | 46 | 943 |
| Containers & Trade | 26 | 482 |
| Light & Fire | 6 | 192 |
| Signs, Art & Writing | 35 | 1943 |
| Magic & Religion | 31 | 714 |
| Death & Battle | 19 | 882 |
| Machines, Games & Oddities | 20 | 413 |

`CATEGORY_THEME` in `bin/gen-placeable-appearances.py` is that map, and it is
**hand-made on purpose**: CEP's names carry a long tail of near-synonyms
(`Bone`/`Bones`, `Flower`/`Flowers`, `Ruin`/`Ruins`,
`Obelisk`/`Obelith`/`Obeloid`) that no rule groups sensibly. Re-shuffle it
freely — nothing but the menu's shape depends on it. A category missing from the
map lands in `THEME_FALLBACK` **and the generator prints it**, so a CEP bump that
adds categories is noisy rather than silent. A name listed under two themes is a
hard error.

Within a theme the publisher sorts categories **biggest first**, so page 1 of
every theme is its useful half and the five-entry tail sinks to the back.

`placeappdb` is **not** season-scoped state — it describes the haks, not the
players — but it still lands in this repo's own `NWN_HOME_DIR/database`, so a new
season needs one run of the publisher, the way it needs one run of
`bin/season-shared-dbs.sh`. Re-run both scripts after a CEP bump.

## In game

`graf_use.nss` (pedestal `OnUsed`) takes the claim and opens `graf_conv`.

**One paged menu serves all three levels.** `graf_mode` says whether the nine
slots are showing themes (0), categories (1) or appearances (2), so there is one
set of nine `graf_vis_<i>` / `graf_pick_<i>` scripts, one `graf_page_n`/`_p` pair,
one `graf_has_next`/`_prev` pair and one `graf_up` — not three of each.
`Graf_BuildPage` is the dispatcher; `Graf_PageHeader` is the shared heading /
"Page x of y" / slot-wipe scaffolding. Same shape as `Bst_BuildPage` in
`bst_db.nss`, which is the template to read first.

- Tokens **6500–6518**: 6500 heading, 6501 "Page x of y", 6502 the
  current-selection summary, 6510–6518 the nine row labels.
- Per-PC locals: `graf_mode`, `graf_theme`, `graf_cat`, `graf_page_off`,
  `graf_page_total`, `graf_slot_<i>` (theme name, category name, or the
  appearance id as a string — whichever level is showing).
- *Next look* / *previous look* (`graf_step_n` / `graf_step_p`) step one row
  inside the current category and **wrap**, so neither end dead-ends.

**Name and description** are captured in a small NUI form (`graf_nui_open` /
`graf_nui_evt` / `graf_nui_inc`, shaped after `dye_nui_*`), because a
conversation cannot take typed input. Both fields are pushed onto the canvas with
`SetName` / `SetDescription`, so the preview reads exactly as the finished
graffiti will. Player text is run through `Graf_Sanitize`, which strips `<` and
`>` — that text ends up in an NPC's dialogue line and in the DM's note, and
neither may be able to impersonate a custom token or a colour sequence.

**Nothing reverts.** The pick lives in `graffitidb`, not on the object, so
cancelling the conversation, logging out or rebooting all leave it intact;
`Graf_RestoreCanvas()` in `onmoduleload.nss` repaints the canvas after a restart.

**Claim lock.** The easel is one shared object in a public area, so the first
player to open it claims it (`easel.claim`) and others are told it is in use. The
claim clears on *That will do*, on confirming with Barliman, or after
`GRAF_CLAIM_TTL` (180 s) with no interaction. Every conversation action refreshes
it. Note the conversation deliberately does **not** release on abort: opening the
NUI form ends the dialogue, and releasing there would free the easel mid-edit.

## The merit side

- `Merit_PostRequestHook` (in `merit_redeem.nss`) fires at the end of a
  successful `Merit_RequestById`. For 301 it jumps the player to
  `wp_placeablecustomizer`. Add a branch there rather than another special case
  inside `Merit_RequestById`, which is about accounting.
- `redemptions.note` is a new column, added by a `PRAGMA table_info`-guarded
  `ALTER TABLE` in `Merit_InitDb()` — same shape and same reason as `item_tag`:
  `meritdb` is the **shared cross-season** DB, so anything reading it must
  tolerate the column's absence until each realm loads a module carrying the
  migration. `bin/roadmap_merit.py:has_note_column()` is the reader-side guard.
- Barliman grows one branch, gated on `merit_graf_vis.nss`: **in the Well of Eru**
  *and* holding an open 301 request (`Merit_PendingIdFor`). Anywhere else the
  line is simply absent. `merit_graf_prep` builds the prompt into **token 5039**,
  `merit_graf_ok` gates the Yes, `merit_graf_conf` writes the note via
  `Merit_SetRedemptionNote` and releases the easel.
- It is **re-confirmable**: the request stays pending until a DM fulfils it, so a
  change of heart just overwrites the note.
- The note surfaces in three places: the EmoteWand pending list
  (`Merit_BuildPendingPage` appends it to the row description), the roadmap
  editor's **Pending Requests** panel, and the per-idea **In-game merit** history
  — both as a *Note* column.

## Files

**Host:** `bin/gen-placeable-appearances.py`, `bin/publish-placeable-db.py`.

**Module:** `graf_db.nss` (schema + catalogue reads), `graf_inc.nss` (render,
claim, menus), `graf_use.nss`, `graf_conv.dlg.json`, `graf_pedestal.utp.json`,
`graf_canvas.utp.json`, the menu scripts (`graf_vis_0-8`, `graf_pick_0-8`,
`graf_cats`, `graf_sum`, `graf_step_n/p`, `graf_page_n/p`, `graf_has_next/prev`,
`graf_up`, `graf_in_app`, `graf_done`), the NUI trio, and
`merit_graf_vis/prep/ok/conf.nss`.

**Touched:** `merit_db.nss`, `merit_redeem.nss`, `meritconv.dlg.json`,
`onmoduleload.nss`, `thewelloferu.git.json`, `bin/roadmap-editor.py`,
`bin/roadmap_merit.py`.

## Out of scope, if someone asks

Choosing the graffiti's **position and facing** in game, auto-placing the final
placeable inside `Merit_FulfillRedemption`, and resetting the easel once a
request is fulfilled. All three are natural follow-ups; none is built.

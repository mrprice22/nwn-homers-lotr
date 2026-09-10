# Item appearances: how to pick a `ModelPart1` you have actually LOOKED at

An item's appearance is one integer. Nothing in the toolset, in `unpacked/*.uti.json`,
in the wiki or in `module-index/` says what that integer looks like — so appearances
get chosen by guesswork, and the guess is wrong far more often than it feels.

That is not hypothetical. The whole Crash Party item set shipped with defaults nobody
had looked at, and the result was:

| Item | It was | It actually looked like |
|---|---|---|
| Party Popper | `it_midmisc` 15 | a rolled-up letter |
| Mask of a Thousand Faces | `it_midmisc` 42 | a sealed writ |
| Wishing Coin | `it_midmisc` 51 | a bulletin-board flyer |
| Fireworks Finale Staff | `it_midmisc` 59 | a severed dragon head |
| Drum of the Marching Band | `it_midmisc` 68 | a torn-out heart |

Each one is a blueprint a player opens their pack and reads a *name* on. **Look at
the icon before you commit the number.**

## The tool

```
python3 bin/gen-item-icon-sheet.py --base 29          # every miscmedium icon
python3 bin/gen-item-icon-sheet.py --class it_glove   # by ItemClass
python3 bin/gen-item-icon-sheet.py --base 29 --only 2,11,12,94   # zoomed comparison
```

It pulls the icons out of the **resman** — stock data, CEP haks and this module's
overrides, resolved exactly the way the server resolves them — and lays them out in a
labelled grid under `module-index/icons/<class>/`. The icon file *is* the appearance:
`iit_midmisc_051.tga` is what `ModelPart1: 51` looks like in a player's inventory.

Extraction scans the whole 4 GiB CEP resman and takes **several minutes per class**,
so the raw icons are cached under `module-index/icons/<class>/raw`; `--refresh`
re-extracts. Like everything in `module-index/`, that directory is gitignored —
regenerate it, don't commit it. The findings belong in this file instead.

**Two icon families**, and the tool handles both because you need both:

- **Simple items** (`ModelType` 0/2 in `baseitems.2da` — every misc class, wands,
  rods) carry `iit_<itemclass>_<nnn>.tga`, sometimes shadowed by a `.dds`.
- **Armour parts** (`ModelType` 1 — helmets, cloaks, armour) carry
  `i<part>_<nnn>.plt` instead. PLT is a two-byte-per-pixel paletted format whose
  colours are chosen at runtime from the wearer's dyes, so the tool renders the
  colour channel as **greyscale**: the tint is lost, the SHAPE survives, and shape
  is the question you are asking ("is this a crown or a great helm?").

## Rules that constrain the choice

**An activated item must sit on a non-equippable base item.** A "use it from your
pack" item that can be equipped ends up worn, and the activation goes with it. The
non-equippable classes (`EquipableSlots` `0x00000`) worth knowing:

| Base | label | ItemClass | Inventory | Good for |
|---|---|---|---|---|
| 24 | miscsmall | `it_smlmisc` | 1x1 | coins, gems, trinkets, dolls, small tools |
| 29 | miscmedium | `it_midmisc` | 2x2 | the default junk drawer: masks, bombs, mugs, instruments |
| 34 | misclarge | `it_talmisc` | 2x3 | staves, brooms, shovels, tall props |
| 79 | miscthin | `IT_THNMISC` | 1x2 | bottles, tankards, pipes, horns, wands |

**Switching between those four is safe for item properties.** All four share
`PropColumn` 15 in `baseitems.2da`, so a Unique Power (or anything else) survives the
move untouched. Check that column before switching to a base item outside this list.

**Already-minted copies do not change.** An item in a player's pack carries its own
`BaseItem` and `ModelPart1`; editing the blueprint only affects copies created
afterwards. There is no script-side fix — NWScript cannot change an item's base item —
so a re-skin needs the old copies destroyed and re-granted. For the Crash Party that
is what opting out and back in at Bartholomew does.

## Verified catalogue

Everything below was read off a rendered sheet, not inferred from a name. Add to it
whenever you identify another one — that is the point of the file.

### `it_midmisc` (base 29, miscmedium)

| # | What it is |
|---|---|
| 2 | banded wooden tub — the closest thing to a **drum** |
| 4 | harp |
| 11 | engraved stein / tankard |
| 12 | round bomb with a lit fuse |
| 13 | grenade |
| 15 | rolled letter |
| 27 | goblet |
| 32 | letter |
| 38 | cracked porcelain jester mask |
| 39 | painted tiki mask |
| 42 | sealed writ |
| 51 | bulletin-board flyer |
| 57 | gold nuggets |
| 59 | severed dragon head |
| 68 | torn-out heart |
| 90 | gilded sceptre |
| 94 | **two-faced comedy/tragedy theatre mask** |
| 95 | artist's palette |
| 98 | playing cards |
| 103 | coiled rope |
| 122 | bracers |
| 125 | barrel |

### `it_smlmisc` (base 24, miscsmall)

| # | What it is |
|---|---|
| 6 | puppet / poppet doll |
| 21 | beach ball |
| 75 | lollipop |
| 78 | **stamped gold coin** |
| 82 | metal bars |
| 99-101 | birds (dove, pigeon, raven) |

### `it_thnmisc` (base 79, miscthin)

| # | What it is |
|---|---|
| 3 | **foaming beer mug** |
| 6 | flagon / lantern |
| 7 | pan pipes |
| 8 | horn |
| 13 | gold chalice |
| 51 | golden spray, reads as a firework |

### `it_talmisc` (base 34, misclarge)

| # | What it is |
|---|---|
| 3 | broom |
| 4 | pickaxe |
| 5 | shovel |
| 9 | gold sceptre |
| 21 | **tall gilded staff** |
| 22 | golden idol |

### `it_glove` (base 36, gloves)

| # | What it is |
|---|---|
| 1 | plain leather gloves |
| 2 | **plated, studded gauntlets** |
| 11 | skeletal claw |

### `helm` (base 17, helmet — PLT, greyscale shapes)

| # | What it is |
|---|---|
| 26 | skull helm |
| 30 | **spiked crown-helm** — the nearest thing to a crown |
| 32 | horned great helm with a face |
| 34 | Witch-king-style crowned hood |

### `cloak` (base 80)

Icons 1-14 are all cloaks and differ only in colour and clasp; 8 is a pale
grey-blue, 14 a shaggy orange. The CEP models above 50 that the module uses widely
(51-58) have **no** icons of their own in the resman.

## What the Crash Party set landed on

| Blueprint | Base | Model | Reads as |
|---|---|---|---|
| `cp_tankard` Magical Tankard | 79 | 3 | foaming beer mug |
| `cp_souvenir` Commemorative Tankard | 29 | 11 | engraved stein |
| `cp_coin` Wishing Coin | 24 | 78 | gold coin |
| `cp_mask` Mask of a Thousand Faces | 29 | 94 | two-faced theatre mask |
| `cp_popper` Party Popper | 29 | 12 | bomb with a lit fuse |
| `cp_strings` Puppet Strings of Bard's Folly | 24 | 6 | puppet doll |
| `cp_drum` Drum of the Marching Band | 29 | 2 | banded drum |
| `cp_fireworks` Fireworks Finale Staff | 34 | 21 | tall gilded staff |
| `cp_crown` Crown of Cacophony | 17 | 30 | spiked crown |
| `cp_gloves` Gloves of a Great Many Punches | 36 | 2 | plated gauntlets |
| `cp_cloak` Cloak of a Thousand Faces | 80 | 8 | pale shifting cloak |

Nothing in the game data is a marching drum, a party popper or a firework rocket, so
those three are the nearest honest reads rather than exact matches. If a CEP class
turns up something better, this table is the place to record it.

# Testing guide — Item Tag Dedup

**Build:** item-tag dedup (commit `74803a6f53a`)
**Audience:** testers / DMs
**Time to test:** ~30–45 min for the core checks; more if you want to sweep quests.

---

## What changed (plain-English)

Lots of different items in the module were secretly sharing the same internal
**Tag** (the hidden name scripts and the game use to identify an item). When two
*different* items share a tag, the game can't tell them apart — that's what
caused the **Longsword of Elrond "false jailing"** bug (a legit sword kept
getting flagged as illegal contraband).

This build gives **every distinct item its own unique tag**. Under the hood:

- Some items just had their tag renamed.
- Some "custom" copies of items (a merchant's or an NPC's tweaked version) were
  turned into their **own separate blueprint** with a new internal id.
- Items **equipped on creatures** were handled carefully so monsters/NPCs still
  respawn wearing the right gear.

**361 of 369 conflicts were fixed.** 8 were left alone **on purpose** (see
"Deliberately unchanged" below) because their tag is used by a quest and
renaming them could break that quest.

**Nothing about how items look, what they do, their stats, or their value
changed.** Only hidden internal names/ids changed.

---

## The #1 thing to test: no false "contraband" jailing

The old bug jailed players for carrying **legitimate** high-end gear when they
logged in or entered the **Well of Eru** (the Forge Warden's contraband scan).
The fix was specifically designed so this can't happen — **please try hard to
break it.**

### Test A — carry your existing gear through the scan
1. Log in with a character that already owns high-value/enchanted gear
   (especially anything looted or bought **before** this build).
2. Walk into the **Well of Eru**.
3. **Expected:** you are NOT jailed, the Forge Warden does NOT accuse you, no
   `<UNRECOGNIZED TOKEN>` message.
4. ⚠️ **Please also test items pulled out of your BANK / player-house chest**,
   not just what you were carrying — banked items are the most likely to trip a
   contraband check if anything was missed.

### Test B — the Longsword of Elrond itself
- Grab/loot the **Longsword of Elrond** (Elrond in Rivendell, or Card Mennard's
  copy in Edoras). Carry it into the Well of Eru. **Expected:** no jailing; both
  swords work and look normal.

### Test C — re-color / re-shape an item (Bree appearance station / dye kit)
- Dye or reshape a valuable item, then walk into the Well of Eru.
- **Expected:** still no false jailing. (A related past bug jailed players after
  they recolored an item — worth re-confirming.)

**If anyone gets jailed by the Forge Warden for legit gear, that's a P1 bug —
grab the character name, the item, and where/when it happened.**

---

## Core item sanity checks

For a spread of items — cheap, mid, and top-tier — confirm the basics still work:

- [ ] **Loot** it off a creature/chest — it appears, correct name, correct stats.
- [ ] **Buy/sell** it at the relevant merchant — price unchanged, transaction works.
- [ ] **Equip / unequip** it — bonuses apply, no error.
- [ ] **Stack** stackable items (arrows, potions, gems) — they still stack.
- [ ] Item **name and description** read correctly (in-game and on the wiki).

Good candidate items to spot-check (all were touched by the dedup):

- **Longsword of Elrond** (Elrond, Card Mennard)
- **Chain of The Guardian** / Adamantine armors
- **Black Galvorn Plate** / Plate of the Witch King (Ronus crafting quest — see below)
- **Gloves / Epic Gloves of the Stone Heart** (Ronus crafting quest)
- Boss-dropped rings/plates, Galadhrim gear, Drider/Numenorean gear
- Anything sold by major merchants (Rivendell, Bree, Edoras, forges)

---

## Creature respawns (equipment)

Equipped gear on monsters/NPCs got special handling so respawns stay correct.

- [ ] Kill a named/boss enemy that carries distinctive gear.
- [ ] Let it respawn (or reboot).
- [ ] **Expected:** it comes back wearing the **same** weapon/armor as before —
      no "reverted to a generic version," no missing weapon.

Watch especially: **Card Mennard (Edoras)**, Rohirrim soldiers, Galadhrim
guards/archers, Drider priestesses/militia, Black Numenorean casters, Dol-Guldur
defenders, and any boss you know the loadout of.

---

## Quests — the 8 deliberately-unchanged items

These 8 items were **left exactly as-is** because a quest looks them up by tag.
They should behave **identically to before** — the point of testing them is to
confirm we correctly *avoided* touching them. If any of these quests broke, it's
unrelated to this build, but please report it anyway:

| Item / tag | Where it matters |
|---|---|
| **Boss Ring** (`BossRing`) | boss-ring turn-ins / rewards |
| **Dye Kit** (`DyeKit`) | the dye/recolor system |
| **Denethor's Plate** (`DenethorsPlate`) | related turn-in |
| **Gandalf's Epic Ring** (`EpicRing`) | related turn-in |
| **Witch Weed** (`witchbud`) | donation / herb turn-in |
| **"Proof" item** (`nw_wplmsc004`) | the proof turn-in at the reward NPC (at_036/sc_021) |
| **Black Galvorn Plate** (`BlackGalvornPlate`) | Ronus crafting/transmute quest |
| **Epic Gloves of the Stone Heart** (`X2_IT_MGLOVE018`) | Ronus crafting/transmute quest |

- [ ] Run each of these turn-ins/crafts end-to-end. **Expected:** works as before.

---

## Possible issues / impacts to watch for

- **Duplicated-looking items on the wiki (expected, not a bug):** some items that
  were "one item with two versions" are now correctly shown as **two separate
  items** with distinct names/ids. The wiki updates on the next scheduled
  refresh, so it may briefly look inconsistent until then.
- **Old vs new copies:** an item you looted *before* this build and the *same*
  item looted *after* may now have slightly different internal ids. Both are
  legal and both work — this is expected. (The forge whitelist was specifically
  updated to keep the older copies legal.)
- **Merchant "custom" stock:** a few merchants sold hand-tweaked versions of
  items; those are now their own blueprints. Confirm the merchant still lists
  them and they still buy/sell.
- **Tag-based scripts:** general item scripts were reviewed and quest lookups
  protected. If a *script/quest* stops recognizing an item you're carrying,
  note the exact item + quest + NPC.
- **Banked / player-house stored items:** most likely place for an edge case to
  hide. Please pull stored gear out and re-check it (Test A, step 4).

---

## How to report

For anything unexpected, include:

- Character name + the item (exact in-game name).
- Where it came from (looted where / bought where / how long you've had it).
- What you did and what happened (screenshot of any error/jail message helps).
- Whether it was a **freshly-obtained** copy or one you've **had since before
  this build** (this distinction matters a lot for diagnosis).

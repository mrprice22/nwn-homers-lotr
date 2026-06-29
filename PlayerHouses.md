# Player Houses — developer notes

The module's player-house feature (first redemption: **Methonash's Place**,
area `area042`, tag `MethonashsPlace`) is built so that **adding a new house is a
data-entry job**, not a code change. Ownership is decided by one key-free table in
the `admindb` campaign DB; the in-house fixtures all ask that table who owns the
house. **No CD keys ever live in `unpacked/`** (see CLAUDE.md secrets rule) — they
live only in the gitignored `bin/seed-admindb.sh`.

## The data model — `admindb.houses`

| column | meaning |
|--------|---------|
| `cdkey` (PK) | owner's public CD key — one home per CD key |
| `player_name` | label only |
| `area_tag` | the house area's tag — ownership anchor for chest + key-ring |
| `home_wp_tag` | waypoint the rest-menu "Home" option teleports to |
| `key_resref` | door-key item resref the key-ring dispenses |

Created idempotently by `Admin_InitDb()` (`unpacked/admin_db.nss`, called from
`onmoduleload.nss`). Helpers, all SELECT-only:

- `Admin_HasHome(oPC)` — does this CD key own a home?
- `Admin_GetHomeWP(oPC)` — home waypoint tag for this CD key.
- `Admin_OwnsAreaHouse(oPC, sAreaTag)` — does this CD key own the house in `sAreaTag`?
- `Admin_GetHouseKeyResref(sAreaTag)` — door-key resref for that house.

Seed rows out of band in `bin/seed-admindb.sh` (gitignored), then re-run it on the
server and **restart** so the StartingConditionals re-read live rows.

## Reusable fixtures (already built)

- **"Home" teleport** — first row of the main rest-menu *Teleports* submenu
  (`emotewand.dlg`, ENTRY 5). Gated by StartingConditional `_hashome`; action
  `_gohome` jumps to `home_wp_tag`. Generic — every house owner sees "Home".
- **Persistent chest** — visible chest placeable runs `meth_chest_open` (OnUsed).
  The visible chest carries **no inventory** (`HasInventory=0`) so it can't
  auto-open; access is gated by `Admin_OwnsAreaHouse`, and items live in an
  invisible per-owner locker (`meth_chest_inv.utp`, OnInvDisturbed
  `meth_chest_disturb`) backed by the legacy campaign object store
  (`housechest` DB, keyed by CD key → items persist across all of that account's
  characters). Shared helpers in `meth_house_inc.nss`.
- **Key-ring** — placeable runs `meth_keyring_use` (OnUsed): owner gets a fresh
  copy of `key_resref` each use; anyone else gets 50 dmg + "You are not authorized
  to use this" (`MethZapUnauthorized`).
- **Store** (optional per house) — a Well-Mart clone with a custom buy cap. For
  Methonash: store blueprint `methmart.utm` (MaxBuyPrice 100000), a Store instance
  in the area `.git` `StoreList` tagged `methmart`, opened by `openstoremeth` via a
  one-line greeting conversation `methmart.dlg` set as the NPC's Conversation.

## New-house checklist

1. Build the area; place a teleport **waypoint** (note its tag) and the door.
2. **Door**: `OnOpen = close_door_lock` (auto-closes ~2s later and re-locks),
   `OnMeleeAttacked = _attackplaceable`, `KeyRequired = 1`, and a key item.
3. **Persistent chest** placeable: `HasInventory=0`, `Useable=1`,
   `OnUsed = meth_chest_open`. The script reads ownership from
   `GetTag(GetArea(OBJECT_SELF))`, so it works in any house unchanged — just make
   the area's tag match the `houses.area_tag` you seed.
4. **Key-ring** placeable: `OnUsed = meth_keyring_use`, `HasInventory=0` (also
   reads the area tag dynamically).
5. **Leash**: area `OnEnter = leash_to_area`; house NPCs keep an OnSpawn that runs
   `x2_def_spawn` (records the leash home).
6. **Add the `houses` row** in `bin/seed-admindb.sh` (cdkey, area_tag, home_wp_tag,
   key_resref); re-run + restart.

The chest/key-ring scripts, the DB schema, and the "Home" teleport are all fully
generic — a second house needs no new scripts, only the placeable wiring above and
one `houses` row.

## De-exploiting house NPCs (review pattern)

For static house NPCs (e.g. the two Methonash NPCs): empty `SpecAbilityList`
(zeroes all spell/creature-like uses), empty non-equipped `ItemList`, strip every
equipped item's `PropertiesList`, keep `FeatList` (proficiencies — else the
Jasperre AI unequips the gear). Cosmetic evil weapon glow is re-applied at spawn by
`meth_npc_spawn` (`ItemPropertyVisualEffect(ITEM_VISUAL_EVIL)` — same call the Bree
`weaponfx` NPC uses). No lootable items, no creatures that can leave (leash), door
stays locked.

# Crash Party: the in-game event

The chaos-item event that runs *during* a crash party. The **ops** half — tick
rate, profiler, crash capture, which realm — is a separate document,
[CLAUDE-crash-party.md](CLAUDE-crash-party.md), and the two do not overlap. Read
that one for "how do I measure it"; read this one for "what is in the module".

Everything here is prefixed `cp_`.

---

## The two switches, and what each one actually gates

| Flag | Where | Gates |
|---|---|---|
| `CP_MODE` | LocalInt on the module | **The dispenser, and nothing else.** |
| `CP_WAVE` | LocalInt on the module, 0-3 | Which items the dispenser will hand out. **Global, never per-PC.** |

Both are non-persistent on purpose: **a reboot always ends the party.** That is
the failsafe you want on a box that reboots itself at 03:00 (`dbg_combat.nss` is
the precedent for the pattern).

**`CP_MODE` does not gate item USE.** An item already in a player's pack works
whether the party is on, off, or three months finished. This is not an
oversight — see "Charges" below.

## Waves, and why there is no progress gate

The DM raises `CP_WAVE` and that wave unlocks **for everyone at once**. Players
standing in the Well are topped up on the spot by the lever; anyone arriving
later is caught up on entry by `cp_eru_enter.nss`, which hands over *everything*
from wave 0 up to the current wave that they have not already had.

So a player who logs in during wave 3 walks out with waves 0, 1, 2 and 3
together. There is deliberately **no "use five poppers to unlock the gloves"
mechanic anywhere**: the event exists to set a peak-concurrent-players record,
and a grind gate punishes exactly the latecomers who push that number up, while
generating support questions during the two hours you least want them.

Per-character "already had this" flags live in the `crashpartydb` campaign DB,
not in PC locals, so a relog cannot re-trigger a grant. Same reasoning as the
`gondor-scribe` relog-farm fix.

## Charges: generous, invisible, permanent

Items expire on a **use count only**. There is no real-time cap, and **nothing
expires when the party ends**.

- Counts are set high (Tankard 500, Popper 400, Strings 400, Mask 300, Coin 240,
  Fireworks 120) so nobody rations during the event.
- **Never tell the player the count.** Not in the description, not in a message,
  and never via `SetItemCharges` — that is client-visible and resets when a
  blueprint respawns, which is why the module already avoids it. The break
  message is the only signal a player ever gets.
- The counter is a LocalInt on the item, which serialises into the `.bic`, so
  leftover charges survive logout, reboot and the end of the event.

**Nothing in the codebase removes a player-held `cp_*` item.** There is no
reclaim lever and no sweep that reaches inventories. The only thing that ever
destroys one is that item spending its last charge, in its owner's own hands.

## Cleanup is DM-spawned objects only

`cp_sweep.nss` (the CLEAR ALL lever, and once at module load) destroys objects
tagged **`cp_load`** — creatures and placeables the stress dials spawned — and
filters on nothing else. Keep that filter exactly as narrow as it is.

---

## Files

| File | What |
|---|---|
| `cp_inc.nss` | State, broadcast, spam guard, `CP_ConsumeUse`, the item table, `CP_GrantUpToWave` |
| `cp_db.nss` | `crashpartydb`: sip counts, grant flags, peak record |
| `cp_dm_inc.nss` | Console gate (`Admin_CanAdmin`), venue lookup, dial caps |
| `cp_tankard` / `cp_tipsy` | The mascot and its after-effects chain |
| `cp_popper`, `cp_strings`, `cp_mask` (+`cp_maskoff`), `cp_coin`, `cp_fireworks` | The other five items |
| `cp_eru_enter.nss` | Well of Eru OnEnter wrapper: souvenir + catch-up grant |
| `cp_login.nss` | Per-login hygiene (see the traps below) |
| `cp_peak.nss` | New-record detection and broadcast |
| `cp_board.nss` | The player-facing scoreboard placeable |
| `cp_sweep.nss` | Destroys `cp_load` objects |
| `cp_master`, `cp_waveup`, `cp_wavedn`, `cp_count`, `cp_announce`, `cp_uat`, `cp_clearall`, `cp_dial_*` | The ten control-room levers |
| `x0_s3_clonefist.nss` | **Not part of the event.** Override of the stock Flame Twin script; see below |
| `bin/crash-party-db.py` | Host-side: status, leaderboard, grants, reset-grants, set-peak |

Dispatch: every item's **Tag == ResRef == script name**, and `dmfi_activate.nss`
carries one `cp_` prefix branch that covers all of them, so no future item needs
to touch that shared file. That branch sits **above** the X2 tag-based hook
deliberately — the hook dispatches on tag too, so below it every `cp_` script
would run twice.

---

## Traps this system already fell into

Recorded because each one is invisible until it bites, and several are general.

**A clone of a player must carry nothing real.** Not an event trap, but found
while building it and fixed here: the stock `x0_s3_clonefist` (item property
"Flame twin", `iprp_spells` 442 -> `spells.2da` 615) builds its clone with
`CopyObject(oPC, ...)`, which copies inventory **and equipment**. Plot does not
stop pickpocket, and `disarm_catch.nss` only reconciles disarms where the victim
is a PC — so the clone could be robbed or disarmed for real duplicates. The
override strips carried inventory and locks equipped slots. Full note in
[CLAUDE-gotchas.md](CLAUDE-gotchas.md).

**Anything that survives a logout needs a login fix if its timer does not.**
Two of the six items hit this, and both were silent:

- `SetCreatureAppearanceType` writes `Appearance_Type`, a **saved `.bic` field**,
  while the Mask's revert is a `DelayCommand` that dies at logout. Log out
  masked and you are a penguin permanently. `cp_login.nss` restores it.
- The tipsiness counter is a creature local (saved) while the chain that decays
  it is a `DelayCommand` (not saved). `cp_login.nss` resets it.

**The bonus ledger is not safe for a throwaway item.** The Wishing Coin
originally granted +2 attack through `BPool_Set`. Ledger entries are LocalInts
on the creature (saved); their expiry is a `DelayCommand` (not saved); and
`BPool_ClearTransient` only sweeps sources in the ledger's **own source table**,
which an ad-hoc `"cp_coin"` is not in. Flip, log out inside the minute, come back
with a permanent +2. Every coin row is now a temporary **effect** instead, which
the engine drops at logout. *If you ever add a ledger source from a party item,
it must be registered in the ledger's source table or it will leak.*

**A self-scheduling chain must be started exactly once.** `cp_tipsy` tail-
schedules itself, so kicking it off on every sip started a second chain on the
second drink and a third on the third — belches multiplying geometrically. The
guard is a **timestamp** (`CP_TIPSY_NEXT`), not a boolean: creature locals are
saved into the `.bic`, so a flag stranded TRUE by a restart would have locked the
chain off permanently, whereas a stale timestamp just falls into the past.

**Puppet Strings had to be restricted to PC targets.** The effect is
`ClearAllActions` plus an animation. On another player that is a joke they walk
out of; on a hostile NPC it is a **functional stun** that interrupts a cast or a
swing, and at 400 charges it trivialises every boss in the module. Target
restriction removes the exploit rather than trying to tune around it.

**Anything spawned at a party carries nothing.** `cp_loadmob` has no inventory,
no equipment, `Lootable=0`, `Disarmable=0`, `Plot=1`. A pickpocketable spawned
NPC is the classic duplication bug.

---

## Running one

1. **Control room** (rest menu -> Admin Options -> Teleports -> The Control Room).
2. `cp_announce` for the countdown — press it at T-60, T-30, T-10 and go-time.
3. `cp_master` to open the dispenser. Players collect from the Well of Eru.
4. `cp_waveup` to escalate. Everyone present is topped up immediately; latecomers
   catch up on entry.
5. Stress dials in steps, watching the tick rate — never all at once. `cp_count`
   to read the console, `cp_clearall` to drop the load instantly.
6. `cp_master` again to close the dispenser. **Nobody loses anything.**

**The dials are the load test, not the player items.** Ten people with wands is
an ordinary evening on this box; a dial you can step up one notch and switch off
is what produces an attributable number. Player items are the *reason people are
online*, which is a different job.

`cp_dial_item` is the one to step most carefully: `AIUpdateItem` was measured at
~92 ms/s on the live realm against 0.8 ms/s empty, against an AI update list
already ~23,400 objects.

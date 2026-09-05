# Merit Award & Redemption system

Persistent, DM-awarded contribution points ("merit") that players redeem for
rewards. Account-wide (keyed on `GetPCPublicCDKey`, **not** per-character).
Player-facing copy and the full reward catalogue live on the wiki:
`docs.manual/Customizations.html#merit`. This file is the implementation map.

## Storage — campaign DB `meritdb` (SQLite)

Three tables, all created idempotently by `Merit_InitDb()` (called on login from
`mod_cliententer.nss`, the module's `Mod_OnClientEntr` handler). All access goes
through `SqlPrepareQueryCampaign`.

- **`players`** — `cdkey PK, name, last_login, bugs, exploits, features, uat,
  merit_spent`.
  - **Earned merit is never stored or decremented.** It is computed on demand:
    `earned = bugs*1 + exploits*3 + features*2 + uat*1`
    (defect 1, feature 2, exploit 3, UAT 1).
  - **`uat` credits VALIDATION, not reporting.** It is the one counter not tied
    to submitting an idea: it pays whoever helped verify a fix. Several players
    can be credited for the same roadmap item, and none of them need be the
    reporter — which is why it is its own column with its own flat rate rather
    than a fourth idea `type`.
  - **`uat` is added by an `ALTER TABLE` migration**, not by `CREATE TABLE IF NOT
    EXISTS` (which never alters an existing table). It is guarded by a
    `PRAGMA table_info(players)` check, copying the older `redemptions.item_tag`
    pattern directly above it. Because `meritdb` is the **shared, cross-season**
    database, the column appears for every realm as soon as *any* of them loads a
    module carrying this `merit_db.nss` — so anything reading it must tolerate
    its absence until then (`bin/roadmap-editor.py` does, via `_has_uat_column()`).
  - **Spending is tracked only by `merit_spent`** (the escrow counter).
  - `available = earned - merit_spent` → `Merit_Available(cdkey)`.
- **`redemptions`** — `id PK, cdkey, player_name, reward_id, reward_label, cost,
  needs_dm, status, requested_at, resolved_by, resolved_at, item_tag, note`.
  - **`note`** is the only place a request can say what the player actually
    wants, in their own words. Today it carries the graffiti reward's chosen
    appearance/name/description, written by `merit_graf_conf.nss` through
    `Merit_SetRedemptionNote` (see [CLAUDE-graffiti.md](CLAUDE-graffiti.md)).
    Like `item_tag` it is an `ALTER TABLE` migration, so every reader must
    tolerate its absence — `bin/roadmap_merit.py:has_note_column()` is the
    out-of-game guard, and `Merit_BuildPendingPage` uses `COALESCE(note,'')`.
  - `status` lifecycle: `pending → fulfilled | cancelled`. Instant rewards are
    inserted already `fulfilled` with `resolved_by='auto'`.
- **`merit_ledger`** — append-only audit log of every merit movement: `id, cdkey,
  player_name, delta` (`<0` spent, `>0` refunded/awarded), `balance_after,
  reason, redemption_id, created_at`. Written by `Merit_Ledger(...)` on every
  request/instant/tournament spend, every cancel refund, every DM award and
  every UAT credit (`award: UAT validation`), so
  spends are always recoverable even after a reward's placeholder is removed.
  Never pruned; lives in the same `meritdb.sqlite3` so the daily backup covers it.

### Delivery classes & escrow model (how spending works)

Each reward is **instant** (`needs_dm = 0`) or **DM-fulfilled** (`needs_dm = 1`).
The player always sees a **confirmation step** (entry `e_confirm_choice`, dynamic
text in token 5037, set by `Merit_PrepConfirm`) that states which it is and, if
they can't afford it, says so up front (no "Yes" offered).

- **DM-fulfilled** → **Request** (`Merit_RequestById`): affordability check
  (`available >= cost`, so `merit_spent` can never exceed earned), `Merit_Spend`
  debits the cost, a `pending` row is inserted, DMs are alerted. The cost is
  *held*; a DM later **Fulfills** (`Merit_FulfillRedemption` — debit stays) or
  either side **Cancels** (`Merit_CancelRedemption` — `Merit_Refund`, clamped at
  0). A player may cancel only their own; a DM may cancel any.
- **Instant** → **Grant** (`Merit_GrantInstant`, or `Merit_GrantTournament` for
  tournament gear): affordability check, `Merit_Spend`, a row inserted already
  `fulfilled`/`auto`, ledger entry. Tournament gear delivers an item
  (`CreateItemOnObject`); **teleports and premium boosts are no longer nominal** —
  `Merit_GrantInstant` enforces teleport unlock ordering/ownership
  (`Merit_IsTeleReward` / `Merit_TeleOwned` / `Merit_TelePrereqMet`, ownership
  recorded as a `fulfilled` redemptions row per CD key) and enqueues real 2x
  gold/XP subscriptions for 201-204 via `Boost_Reconcile` / `Boost_Enqueue`, both
  wired at login from `mod_cliententer.nss`. The ledger is why any remaining
  nominal spend stays auditable.
  - **`Merit_GrantTournament` is delivery-safe / spend-last:** it creates the
    item and checks `GetIsObjectValid(oItem)` **before** calling `Merit_Spend`.
    Only a truly failed creation (bad blueprint → invalid object) aborts with
    **no merit charged**. A full inventory is *not* a failure: NWN still creates
    the item but drops it at the PC's feet, so `GetItemPossessor(oItem) != oPC`
    is treated as "delivered, on the ground" — merit **is** charged and the
    player is told to pick it up. Any new instant reward that hands a player
    something real must follow the same deliver-then-charge order so a failed
    creation can never bill the player.

**Graffiti (301) is DM-fulfilled but no longer blind.** Requesting it teleports
the player to the Well of Eru (`Merit_PostRequestHook`), where an easel lets them
pick any placeable appearance in the game and name it; confirming with Barliman
writes that onto `redemptions.note`. The DM still places the real placeable by
hand. Full map: [CLAUDE-graffiti.md](CLAUDE-graffiti.md).

Current `needs_dm = 0` (instant): teleports 101–107, all premium 201–204,
tournament gear 302. `needs_dm = 1` (DM): graffiti 301, wallet 303, **Become a
DM 304 (100 merit)**, housing size 401–408, housing add-ons 501–505.

Helpers live in `merit_db.nss` (schema, balance, spend/refund, award, NPC stat
tokens, DM award list) and `merit_redeem.nss` (catalogue + request/cancel/
fulfill + list builders).

## Catalogue — single source of truth: `merit_redeem.nss`

`Merit_GetReward(int nId)` returns `{valid, cost, needs_dm, label}` for a reward
id. Ids are grouped by category, and `Merit_CatReward(cat, idx)` /
`Merit_CatCount(cat)` map a category to its ids:

| Category (`MERIT_CAT_*`) | ids | grouping |
|---|---|---|
| `TELE` (0)      | 101–107 | teleport & travel |
| `PREM` (1)      | 201–204 | premium (3x gold & XP) |
| `VANITY` (2)    | 301–304 | vanity & swag (incl. tournament gear 302, Become a DM 304) |
| `HOUSESIZE` (3) | 401–408 | player home, by area size |
| `HOUSEFEAT` (4) | 501–505 | player home add-ons |

Options that are still **unwired** ship as a **placeholder** (red `[PLACEHOLDER]`
prefix via `MERIT_PH` — a literal carrying the raw colour bytes `<c FF 01 01 >`,
null-free red). `Merit_BuildCategory` only applies the prefix to the nominal
instant rewards (teleports/premium); **DM-fulfilled options** (`needs_dm == 1`,
delivered by a DM today) and **tournament gear (302)** (delivered on the spot)
carry **no** prefix. Selecting an option leads to the confirmation step, not a
direct request.

### To ADD a redemption option

1. Add a `case` to `Merit_GetReward` (id, cost, `needs_dm`, label — keep labels
   ASCII to be safe in `.nss`).
2. Register the id in `Merit_CatReward` and bump the category's `Merit_CatCount`
   (each category sub-menu shows up to 9 options — split into a new category if
   you exceed 9).
3. No DB change is needed for a new placeholder option; no new dialog node either
   (categories render their options through the shared 9 option slots).

### Tournament gear (reward 302) — special instant picker

302 is instant but, instead of a one-shot grant, opens a paged item picker
(`Merit_BuildTournament` → tokens 5070–5078, locals `merit_tslot_<i>`(+`_name`)).
Choosing fires `merit_tgrant_<i>` → `Merit_GrantTournament` which spends, records
a fulfilled row + ledger, and `CreateItemOnObject`s the chosen blueprint. The
curated list is `Merit_TournResref/TournName/TournCount` — edit those to change
the offered set.

### To GRADUATE a placeholder to a real automated reward

For an **instant** reward, deliver the effect inside `Merit_GrantInstant` (it
already spends, inserts a `fulfilled` row, and ledgers) — e.g. branch on the
reward id and apply the teleport/premium effect — then drop that option's red
`MERIT_PH` prefix in `Merit_BuildCategory`. For a **DM** reward, deliver inside
`Merit_FulfillRedemption`. `needs_dm` controls which path an option takes; flip
it in `Merit_GetReward` if a reward changes class. Keep the `Merit_Spend` /
`Merit_Ledger` accounting intact.

## Custom token map (avoid collisions)

`SetCustomToken` is module-global. Ranges in use:

| Tokens | Used by |
|---|---|
| 5001–5010 | DM **award** list (`Merit_BuildPage`, `merit_db.nss`) |
| 5011      | DM award: selected player name |
| 5028-5029 | Player stat block: UAT validations, and the points they are worth |
| 5020–5027 | Player stat block (`Merit_SetNpcTokens`) |
| 5037      | Player **confirmation** prompt (`Merit_PrepConfirm`) |
| 5038      | DM **redemption** detail: selected request |
| 5039      | Player: graffiti (301) "is this the one?" prompt (`merit_graf_prep`) |
| 5040–5049 | DM redemption pending list (5049 = header) |
| 5050–5059 | Player "my pending requests" list (5059 = header) |
| 5060–5068 | Player category option labels (red placeholder prefix) |
| 5070–5078 | Player tournament-gear picker labels |

Per-speaker locals `merit_lslot_0..8` hold the current list's row/reward id (0 =
empty); the shared visibility conditional `merit_lvis_<i>` checks them, so the
option list, the player's own-pending list, and the DM pending list all reuse one
set of 9 conditionals. The DM list also stashes `merit_lslot_<i>_desc`. The
**confirmation step** uses separate locals (`merit_pick_id/_dm/_afford`) and the
tournament picker uses `merit_tslot_<i>`(+`_name`) / `merit_tpage_off`/`_total`,
all distinct from `merit_lslot_*` so "Nevermind" returns to the option list
intact.

## Conversations & scripts

- **Player:** NPC `merit_keeper` (tag/resref unchanged) — now **Barliman
  Butterbur**, a bartender appearance (`Appearance_Type` 234), placed in
  `theprancingpo001` (Prancing Pony) **and in `thewelloferu`** (the Well of Eru,
  beside the graffiti easel - that second instance is what makes the graffiti
  confirm branch reachable). Conversation `meritconv.dlg.json`: greeting
  → stats → category sub-menus → option slots (`merit_cat_<c>`, `merit_pick_<i>`)
  → **confirmation step** (`e_confirm_choice`: `merit_ci_instant`/`merit_ci_dm`
  gate the Yes; `merit_finalize` commits via `Merit_GrantInstant` or
  `Merit_RequestById`; tournament slots `merit_tvis_<i>`/`merit_tgrant_<i>` with
  `merit_tpage_*`/`merit_thas_*` paging) → `e_done`. Plus a "my pending requests"
  self-cancel branch (`merit_mypend`, `merit_mcanc_<i>`) and a "how do I earn
  merit?" branch with wiki + Discord pointers (valid for zero-merit players).
  When changing the appearance/name, edit **both** the
  blueprint `merit_keeper.utc.json` **and** the placed instance in
  `theprancingpo001.git.json` (the instance carries full overrides).
### Realm gating - the shop trades on production only

The redemption shop is open to **everyone on `SEASON_ROLE=live`, and to
`can_merit` holders (`Admin_CanMerit`) on every other realm** - dev, early access
and retired seasons alike. Merit is account-wide and spending escrows against a
real `meritdb` balance, so a non-production realm redeeming rewards writes
`merit_ledger` rows against merit the live season owes the player.

The switch is `SP_MERIT_SHOP`, **generated** into `unpacked/season_prof_inc.nss`
from `SEASON_ROLE` by `bin/season-profile.py` - never authored, because
`bin/season-promote.sh` copies dev's tree over production's on every release and
would revert a hand edit. Both halves read one predicate,
`SP_MeritShopFor(oPC)` in `unpacked/sp_meritgate_inc.nss`:

- **Conversation (UX).** Entry `e_stats` offers "I'd like to redeem a reward."
  gated on `merit_gate` (shows the catalogue) and, beside it, the same line gated
  on `merit_gate_no` leading to `e_shop_closed`, which says the shop only trades
  on the live realm. The option is never silently absent, and the stats and
  "how do I earn merit?" branches stay open to everyone everywhere.
- **Authoritative.** `Merit_RequestById`, `Merit_GrantInstant` and
  `Merit_GrantTournament` each bail on `!SP_MeritShopFor(oPC)` **before** any
  `Merit_Spend` or `CreateItemOnObject`, so a blocked player is never charged.
  This one guard covers `merit_finalize.nss` and all nine `merit_tgrant_<i>.nss`.

`bin/season-profile.py --check` (a repack build gate, `tests/check_season_profile.py`)
fails the build if either `sp_meritgate_inc.nss` stops reading `SP_MERIT_SHOP` or
`merit_redeem.nss` stops calling `SP_MeritShopFor` - the failure mode being a
literal creeping back in and opening the shop everywhere.

### The `can_merit` tier - the DM side is gated too

**Everything that moves merit is on `admins.can_merit`, not `can_admin`** (2026-08-31).
The two tiers were the same thing until a DM was added who needed the rest-menu
admin perks but must not touch the merit economy - which is account-wide, shared
across seasons, and spends against a real balance the live season owes a player.
`Admin_CanMerit(oPC)` in `admin_db.nss` is the single test, and like the shop
gate it has two halves:

- **Conversation (UX).** The `[Admin] Merit Awards` and `[Admin] Merit
  Redemptions` links out of the Admin Options entry in `emotewand.dlg.json` carry
  `Active = _cdkeymerit`. A `can_admin`-only DM sees the rest of Admin Options
  with both merit lines simply absent.
- **Authoritative.** `merit_award_bug/exp/ftr/uat.nss`, `merit_rfulfill.nss` and
  `merit_rcancel.nss` each open with `if (!Admin_CanMerit(oDM)) { ...; return; }`.
  **This half is the one that matters** - before it existed those six scripts had
  no authorization check of any kind, and `on_mod_rest.nss` opens `emotewand` for
  every PC on rest, so the single link conditional was all that stood between a
  player and an unlimited merit award. Any new merit-admin action script must
  carry the same guard; the read-only list builders (`merit_list_pg.nss`,
  `merit_rlist_pg.nss`, `merit_sel_<i>.nss`) do not need it.

The consequence to remember: **a DM who is not on `can_merit` cannot clear a
pending redemption request**, anywhere. That is intended - fulfilment is the
server owner's job.

- **DM:** the EmoteWand conversation `emotewand.dlg.json`. Branch
  *[Admin] Merit Awards* (existing, grants points — pick a player, then one of
  *Award Defect Report (+1)* / *Exploit Report (+3)* / *Feature Implementation
  (+2)* / **UAT Validation (+1)**, backed by `merit_award_bug/exp/ftr/uat.nss`)
  and *[Admin] Merit Redemptions*
  (new): paged pending list (`merit_rlist_pg`, `merit_rpage_n/p`,
  `merit_rhas_next/prev`, `merit_dsel_<i>`) → fulfil (`merit_rfulfill`) or cancel
  + refund (`merit_rcancel`). Each new request also fires a `SendMessageToAllDMs`
  chat alert.
- **Out of game:** the roadmap editor's **Award merit** button (`bin/roadmap-editor.py`,
  `award_merit()` → `/api/award`, `/api/revoke`) does exactly what the EmoteWand
  branch does — one counter increment plus one `merit_ledger` row — for the idea
  being moved into `status: awarded`, keyed off the idea's `type`. Its rows are
  told apart only by the `(roadmap:<idea-id>)` suffix on the reason. It never
  INSERTs a `players` row (rows are created on login by `Merit_RecordLogin`); an
  unresolvable submitter is an error, and the roadmap status change is rolled
  back with it. See [CLAUDE-roadmap.md](CLAUDE-roadmap.md) → "Pipeline buttons".
- **UAT credit, out of game:** the roadmap editor's per-idea **UAT validators**
  list (`uat_credits` in `roadmap.yaml`) has an *Award +1* / *Revoke* button per
  validator, routed through `/api/uat-award` and `/api/uat-revoke` to the same
  `award_merit(..., kind="uat")`. It is deliberately **per-entry, not per-idea**:
  one idea can pay several validators, each exactly once, guarded by that entry's
  `awarded: true` flag the way the submitter award is guarded by `merit_awarded`.
  The in-game wand branch has **no roadmap-item picker** — the DM is standing
  next to the tester, so it is a flat +1 and the ledger reason carries no idea id.

## Build notes

- The red placeholder prefix bytes can't be typed through normal file writes
  (0xFF isn't valid UTF-8) — they're injected once into `merit_redeem.nss` with a
  Python byte-replace. The same reason is why colour can't live in `.dlg.json`,
  so option labels are built in script and shown via custom tokens.
- Repack with the `repack-homers-lotr` wrapper; the build gates
  (`check-dlg-integrity`, `tests/smoke-test`) and script compilation must pass.
  Conversations that fail the dialog-integrity gate load empty in-game (NPC faces
  you, no window).

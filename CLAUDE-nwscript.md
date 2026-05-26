# NWScript

NWScript is the in-engine scripting language. Files compile to `.ncs` at
pack time; only `.nss` source belongs in git.

## Script entry-point conventions

- **Event scripts**: `void main() { … }` — no return.
- **Dialogue conditionals**: `int StartingConditional() { … return TRUE/FALSE; }`.
- **Tag-based item events** (used in this module via the Bedlamson
  Dynamic Merchant System hookups): functions with reserved names like
  `OnAcquireItem`, called via the X2 `nw_o2_coninclude` dispatcher.
- **Includes**: `#include "<name_without_ext>"` — pulls in another
  `.nss`. Cyclic includes are a compile error; nasher follows include
  chains for incremental rebuilds.

## Don't invent NWScript builtins

NWScript has no IDE, no LSP, and no autocomplete. There is no "the
compiler will catch typos at edit time" safety net — the only check is
the repack-time compile pass, and a fabricated identifier in a heavily-
included header (e.g. `mw_unlock_inc.nss`) produces one `UNDEFINED
IDENTIFIER` error per consumer script (we hit 27 copies of one error
from a single bad line). **Verify every engine function you call exists
in the Lexicon (<https://nwnlexicon.com>) before using it.**

Specifically, do NOT assume these exist (they don't):

- `SetFormerMaster` — there is no "former master" concept; `RemoveHenchman`
  alone is the complete dismissal.
- `SetDialogResRef` / `SetConversation` — there is **no runtime setter
  for a creature's `Conversation` field**. To use a different dialogue
  on a runtime-spawned creature, either (a) author a second `.utc.json`
  blueprint with the alternative `Conversation` resref and spawn that
  blueprint instead, or (b) keep one blueprint and gate the alternative
  content inside the dialogue via `StartingConditional` scripts that
  inspect a local variable you set on the NPC after spawning.

When you need an engine function you're not sure of, grep the existing
`unpacked/*.nss` files for it — if the module's framework scripts already
use it, it's real. If nothing references it anywhere, it's almost
certainly not a builtin.

## Module-specific framework prefixes

The module pulls in several established NWN frameworks. Treat their
files as **third-party — don't refactor unless you know the framework**.

| Prefix     | What it is                                     | Notes                     |
|------------|------------------------------------------------|---------------------------|
| `nw_*`     | BioWare base game (NW1) defaults               | Available in CEP/base; don't ship modified copies |
| `x0_* x2_* x3_*` | BioWare expansion defaults (HotU)         | Same                      |
| `zep_*`    | Z-PEP placeable / creature pack helpers        |                           |
| `dmfi_*`   | DM Friendly Initiative (DM tools, dice, dialog tokens) | `dmfi_univ_1..N` are universal action scripts; `dmfi_univ_cond` is a parameterized conditional |
| `dmw_*`    | DM Wand utilities                              |                           |
| `bdm_*`    | Bedlamson's Dynamic Merchants (faction/race-restricted store stocks) | Hooks `OnAcquireItem` |
| `hgll_*`   | Homer's Game Legendary Levels (Letoscript-based level 41–60) | Edit constants in `hgll_const_inc.nss`; uses external Letoscript on the server |
| `pc_export*` | PC autosave on heartbeat                     | Hooked at `Mod_OnModLoad` |

`hgll_const_inc.nss` contains a hard-coded **Windows path**
(`C:/NeverwinterNights/NWN/servervault/`) for Letoscript — leave the
constant alone unless you actually want to enable Letoscript on this server.

## Persistence

The module does NOT use NWNX. Persistence is via:

- `GetLocalInt/Float/String/Object` — per-object scratch state,
  cleared on object destruction or area cleanup.
- `GetCampaignInt/Float/String` — persistent across sessions
  (campaign DB, e.g. the `bankdb` campaign for the in-module bank).
- `pc_export_inc` autosave — periodic per-PC save via the engine's
  `ExportSingleCharacter` hook.

There is no SQL — `GetCampaignInt`-style functions persist to NWN's
campaign database files in `database/<campaign>.bdb`.

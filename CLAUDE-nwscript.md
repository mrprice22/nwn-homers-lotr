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

## Colour tokens in dialogue text

**Never put `<c…>` colour tags directly in a `cexolocstring` dialogue field.** The NWN dialogue engine parses `<…>` as a token reference first; an unknown tag renders as `<UNRECOGNIZED TOKEN>` instead of changing colour.

The correct pattern is a two-step indirection via custom tokens:

**Step 1 — register the colour strings at startup** (`onmoduleload.nss`):
```nss
#include "color"
SetCustomToken(6100, COLOR_RED);
SetCustomToken(6101, COLOR_YELLOW);
SetCustomToken(6102, COLOR_END);   // </c>
```

**Step 2 — reference tokens in dialogue text** (JSON `cexolocstring` `"0"` value):
```
"You must <CUSTOM6100>not do this lightly<CUSTOM6102> — it cannot be undone."
```

When the dialogue renders, `<CUSTOM6100>` expands to the raw `<c…>` bytes, which the renderer then interprets as a colour code.

### `color.nss` — the module's colour include

`unpacked/color.nss` defines named string constants for all common colours and a `ColorString()` helper. Use these; don't invent new byte sequences:

| Constant | Approx colour |
|---|---|
| `COLOR_RED` | Red |
| `COLOR_ORANGE` | Orange |
| `COLOR_YELLOW` | Yellow |
| `COLOR_GREEN` | Green |
| `COLOR_BLUE` | Blue |
| `COLOR_LIGHT_BLUE` | Light blue |
| `COLOR_DARK_BLUE` | Dark blue |
| `COLOR_PURPLE` | Purple |
| `COLOR_LIGHT_PURPLE` | Light purple |
| `COLOR_GRAY` | Gray |
| `COLOR_LIGHT_GRAY` | Light gray |
| `COLOR_WHITE` | White |
| `COLOR_END` | `</c>` — closes the colour span |

`ColorString(sText, COLOR_RED)` is a convenience wrapper that returns `COLOR_RED + sText + COLOR_END`, but it can only be used from NWScript; dialogue fields need the `<CUSTOM…>` token approach.

### Reserved custom token numbers

These token numbers are in use module-wide — don't reuse them:

| Range | Used by |
|---|---|
| 101 | `bankbalance.nss` — gold balance display |
| 698–699 | `xpbank.dlg.json` — XP reserve display |
| 3671–3699 | `bbs_include.nss` — bulletin board system |
| 4958 | Family gold balance |
| 6000–6002 | Bank teller: gold, family gold, XP reserve balances |
| **6100–6102** | **Colour tokens: red, yellow, close (set in `onmoduleload.nss`)** |
| 90001–90002 | `brc_wheel.nss` — prize wheel |

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

## Reward-and-take (anti-farm)

Any script that **grants a reward and consumes a player item** must
re-verify possession **at grant time**, inside the action script — not
only in the conversation's StartingConditional. Otherwise it is open to
the *drop-item farm*: the player reaches the reward reply holding the
required item, **drops it while the conversation is still open**, takes
the reward, then picks the item back up, and repeats forever. The
StartingConditional already passed before the drop, so it protects
nothing here.

```nwscript
object oProof = GetItemPossessedBy(oPC, "wk_proof");
if (!GetIsObjectValid(oProof)) return;   // dropped mid-conversation → bail
DestroyObject(oProof);
GiveXPToCreature(oPC, 500);
CreateItemOnObject("reward_item", oPC, 1);
```

Equivalent guards are fine: the `HasItem(oPC, tag)` helper (wraps
`GetItemPossessedBy`), a stack re-count for multi-item turn-ins, or an
advance-only persistent stage / daily cooldown (`GetCampaignInt` /
`QCD_*`) that makes the reward one-shot regardless. Canonical example:
`unpacked/q_arc_finish.nss`.

The `tests/check_reward_exploit.py` smoke gate flags reward-and-take
scripts that show none of these guards and **aborts the repack**. If a
flagged script is genuinely safe (the reward is independent of the item,
or the "take" destroys a non-inventory object), add an inline
`// reward-exploit-ok: <reason>` marker to silence it.

# Homer's LOTR VEL v3

Source-form mirror of the Neverwinter Nights 1 module **Homer's LOTR VEL v3**,
unpacked for git tracking and LLM-assisted editing.

The original `.mod` is a binary ERF archive (~68 MB, ~7280 resources). This
project keeps each resource as a plain-text file under `unpacked/` — GFFs as
JSON, scripts as `.nss` source — so changes diff cleanly and an LLM can read
or modify them directly.

## Layout

```
nasher.cfg       build-target definition (output filename, source patterns)
unpacked/        the source tree — JSON + .nss (committed)
.nasher/source   path of the .mod to unpack/install (per-machine, gitignored)
dist/            build output (gitignored)
wiki/            generated HTML wiki (gitignored)
.nasher/         nasher's working cache (gitignored)
```

## Round-trip workflow

Driven by `nwn-manager` from the [nwn_manager](../nwn_manager/README.md)
project:

```sh
nwn-manager unpack       # NWN/data/mod/Homer's…v3.mod  →  unpacked/
# ... edit JSON / .nss in unpacked/, commit to git ...
nwn-manager repack       # unpacked/  →  dist/  →  NWN/data/mod/Homer's…v3.mod
nwn-manager wiki         # unpacked/  →  wiki/index.html (multi-page HTML wiki)
# ... open the module in the NWN:EE toolset or run it ...
```

`unpack` overwrites whatever is currently in `unpacked/`; `repack` overwrites
the `.mod` in NWN's modules folder. Source of truth is `unpacked/` + git, not
the `.mod`. The wiki is regenerated only on explicit `nwn-manager wiki`.

## Source `.mod` path

The path to the installed `.mod` is recorded in `.nasher/source` (gitignored,
per-machine). It points at:

```
/home/james/Link to Neverwinter Nights/data/mod/Homer's LOTR VEL v3.mod
```

`nwn-manager` sanitizes the path through `/tmp` before invoking `nwn_erf`,
so the apostrophe in the filename is no longer an issue.

## Wiki

A browsable reference for all areas, creatures, items, quests, and scripts is
published at:

**<https://mrprice22.github.io/nwn-homers-lotr/index.html>**

The wiki is generated from `unpacked/` via `nwn-manager wiki` and deployed
separately; the `wiki/` directory is gitignored.

## Redemption codes

Players redeem codes by typing `Code:<name>` in chat (any channel). The
handler is `unpacked/code_redeem.nss`, wired to `Mod_OnPlrChat`. Matching is
case-insensitive; the chat line is suppressed so the code doesn't broadcast
to other players.

Each redemption is keyed on the player's CD key, so a code can be used at
most once per CD key. Redemptions live in the NWN:EE campaign SQLite
database `coderedeem` (`<server>/database/coderedeem.sqlite3`), table
`redemptions(code, cdkey, redeemed_at)`.

Players see one of:

- **Unknown redemption code.** — the code name isn't defined.
- **That code has expired (was valid until YYYY-MM-DD).** — past expiration.
- **You have already redeemed that code.** — this CD key already used it.
- **Code redeemed successfully!** — reward applied.

### Adding a new code

Edit `unpacked/code_redeem.nss` and add a case in **both** functions:

```nwscript
// Expiration (UTC date, YYYY-MM-DD; "" = unknown code).
string GetCodeExpiration(string sCodeLower)
{
    if (sCodeLower == "freelegendary") return "2026-07-01";
    if (sCodeLower == "mynewcode")     return "2026-12-31";  // ← add
    return "";
}

// Reward.
int ApplyCodeBenefit(string sCodeLower, object oPC)
{
    if (sCodeLower == "freelegendary") { SetXP(oPC, 17498600); return TRUE; }
    if (sCodeLower == "mynewcode")     {                                    // ← add
        CreateItemOnObject("some_item_resref", oPC, 1);
        return TRUE;
    }
    return FALSE;
}
```

Code names in the script must be **lowercase** (the handler lowercases
incoming chat before matching). Advertise them in any case you like —
`Code:MyNewCode`, `code:mynewcode`, etc., all work.

Then `nwn-manager repack` to compile and install.

### Changing or removing an expiration

Edit the date string in `GetCodeExpiration()`. Comparison is `date('now') >
expiration`, so a code with expiration `2026-07-01` stops working on
`2026-07-02` (server time). To make a code permanent, set the expiration to
a far-future date like `9999-12-31`.

To pull a code immediately, set its expiration to a past date or remove its
case from `GetCodeExpiration()` (returning `""` makes it report "Unknown
redemption code.").

### Resetting / inspecting redemptions

Use any SQLite client against `<server>/database/coderedeem.sqlite3`:

```sh
sqlite3 coderedeem.sqlite3 'SELECT * FROM redemptions;'
sqlite3 coderedeem.sqlite3 "DELETE FROM redemptions WHERE code='freelegendary';"
```

Deleting a row lets that CD key redeem the code again.

## Four-class multiclassing

NWN:EE patch 8193.35 added engine support for up to 8 classes. This module
enables a cap of **4 classes** via a server-side `ruleset.2da` override — no
hak changes needed, because `ruleset.2da` is resolved from the server override
folder before any hak and is not distributed to clients via nwsync.

### Current state

- `lotr_rules.hak` — custom hak containing `ruleset.2da` with `MULTICLASS_LIMIT 4`.
  Listed first in `Mod_HakList` (highest hak priority) so it wins over any
  `ruleset.2da` shipped by CEP. nwsync distributes it to clients automatically
  on connect — no manual client-side steps needed.
- `~/.local/share/Neverwinter Nights/override/ruleset.2da` — same file in the
  server override folder, so the server itself also sees `MULTICLASS_LIMIT 4`.
- 11 scripts updated in `unpacked/` to handle a 4th class position:
  `pers_state_inc.nss`, `hgll_featreq_inc.nss`, `bdm_include.nss`,
  `x0_i0_spells.nss`, `my_charfuncs.nss`, `dmfi_dmw_inc.nss`,
  `dmw_func_inc.nss`, `j_inc_generic_ai.nss`, `nw_i0_generic.nss`,
  `nw_o2_coninclude.nss`, `sd_filter_inc.nss`

### Rebuild from scratch (new machine / fresh NWN install)

1. Extract the base `ruleset.2da` from the NWN data files:
   ```sh
   mkdir -p /tmp/nwn_2da
   NWN="$HOME/.local/share/Steam/steamapps/common/Neverwinter Nights"
   ~/.nimble/bin/nwn_resman_extract --root "$NWN" \
     --userdirectory "$HOME/.local/share/Neverwinter Nights" \
     -p "ruleset" -d /tmp/nwn_2da
   ```
2. Edit the extracted file — find the `MULTICLASS_LIMIT` row and change `3` to `4`:
   ```
   519  MULTICLASS_LIMIT                                 4
   ```
3. Build the hak and install it:
   ```sh
   mkdir -p /tmp/lotr_rules_hak
   cp /tmp/nwn_2da/ruleset.2da /tmp/lotr_rules_hak/
   ~/.nimble/bin/nwn_erf -c -f /tmp/lotr_rules.hak -e HAK \
     /tmp/lotr_rules_hak/ruleset.2da
   cp /tmp/lotr_rules.hak \
     "$HOME/.local/share/Neverwinter Nights/hak/lotr_rules.hak"
   ```
4. Copy the 2da into the server override folder too (server-side enforcement):
   ```sh
   cp /tmp/nwn_2da/ruleset.2da \
     "$HOME/.local/share/Neverwinter Nights/override/ruleset.2da"
   ```
5. Repack the module and run the nwsync refresh so clients receive the new hak.

### Rolling back to 3 classes

1. Remove the hak from `Mod_HakList` in `unpacked/module.ifo.json` (delete the
   `lotr_rules` entry).
2. Delete the server override: `rm ~/.local/share/Neverwinter Nights/override/ruleset.2da`
3. Repack and refresh nwsync. Clients will drop the hak on next connect.
4. **Scripts:** The 11 script changes are backward-compatible for 1–3 class
   characters (the extra loop iterations hit `CLASS_TYPE_INVALID` and
   short-circuit). Reverting them is optional; `git revert` the relevant commit
   if you want exact parity with the original.

## Prerequisites

`nasher`, `nwn_gff`, `nwn_script_comp`, and `python3` (for `wiki`) must be
on `PATH`. See [`nwn-manager`](../nwn_manager/README.md) for install
instructions on Bazzite / immutable Fedora.

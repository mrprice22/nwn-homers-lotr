# Dungeon Solitaire — NWN integration (`DungeonSolitaire.Nwn`)

An in-process [Anvil](https://nwn-dotnet.github.io/Anvil/) plugin that runs the
`DungeonSolitaire.Core` C# card game inside the NWN module, in the prepped area
**`area017`** ("Dungeon Solitaire"). Cards are portrayed by NWN creatures and
statues instead of sprites; players read a card by **examining** the figure.

The card-game engine (`DungeonSolitaire.Core`) is a separate project —
[**Dungeon Solitaire**](https://github.com/mrprice22/Dungeon-Solitaire), designed
by Steven Hastings and built by James Price. This plugin is just an NWN front-end
for it, the same way that repo's Godot and console front-ends are; it references
`DungeonSolitaire.Core` unmodified. See the in-game **Credits** placeable
(`DS_credits` in `area017`) for the full credits, mirrored from the upstream
console front-end.

> Credits, in brief: **game design** — Steven Hastings; **engine** — James Price
> (with AI assistance from ChatGPT and Claude); **NWN integration** — James Price
> (Homer's Quest) and Claude (Anthropic), which built this Anvil plugin front-end.

## How it plays

1. A player pulls the **DS_NewGame** lever and becomes the *active player*.
2. The board renders: five enemy columns at the `DS_C{col}_R{row}` waypoints
   (face-down cards are statues, revealed cards are named NPCs) and the player's
   hand of ally NPCs lined up around `DS_Hand` (they spawn at `DS_Hand_SPAWN` and
   walk in).
3. Each turn the player **clicks an ally**, which opens the `ds_attack`
   conversation to pick a target column (or "unleash" for area effects). The ally
   lunges, VFX play, the front enemy takes damage / dies / reveals the next card.
4. When an effect needs a further decision (discard a card, pick a target enemy,
   choose which queued effect fires next, retrieve from the graveyard, a yes/no),
   the **`ds_choice`** popup opens automatically with the real options. If the
   player closes it without choosing, it re-opens a few seconds later (it never
   auto-picks for them). Long lists (e.g. a deep graveyard) page in blocks of ten.
5. An invisible narrator, **"The Dungeon"**, *speaks* the engine's running
   commentary — attacks, effect activation/resolution, deaths, rewards, phase
   banners, win/loss — as in-game talk, colour-coded per log level (mirroring the
   upstream console front-end's palette). Heard by the active player and any
   spectators in the area. Verbosity is tunable via `DsConfig.SuppressedLogLevels`
   (default trims the low-priority `Subtle`/`ExtraInfo`/`Debug` chatter).
6. A revealed enemy's **NWN hit points track its card health** (current/max
   ratio), so the engine's "grazed / badly wounded / near death" tint and health
   bar reflect the card, and its name reads e.g. `Lurtz (HP 3/6)`. Cards are
   `Immortal`/`Plot`; any manual player damage is reverted to the engine value.
7. Win by clearing every column; lose if you run out of allies. The score is
   written to the **DS_HighScore** gravestone and persisted.
8. Bystanders may watch but cannot act. If the active player leaves the area or
   logs out for 30 s, the board clears and the next lever-puller takes over.

## Architecture

| File | Role |
|------|------|
| `DsManager.cs` | Anvil service: wires the lever, gates bystanders, owns the single session, clears the board on abandonment, hosts the `ds_attack` and `ds_choice` conversation script handlers. |
| `DsSession.cs` | One live game: runs the blocking `GameEngine` on a background thread and marshals its `GameEventBus` events onto the main thread; drives the effect-pacing / input handshake, the attack flow, and the secondary-choice popup (builds the menu, sets the dialog tokens, owns the invisible narrator speaker, re-pops on close). Also hooks the engine's `GameLogger` and relays each line as colour-coded narrator talk. |
| `MainThreadDispatcher.cs` | Serializes engine-thread work onto Anvil's main thread (the NWN analogue of Godot's `CallDeferred`). |
| `BoardView.cs` / `CardActor.cs` | Reconcile engine state to spawned statues/creatures; spawn, reveal, reposition, lunge. `CardActor` also maps card health onto the creature's HP and reverts manual damage. |
| `CardCreatureMap.cs` | Card → creature blueprint resref (real matches + Old-Tagget placeholders), the examine-description text, the `Name (HP x/y)` label, and the one-line choice-menu labels. |
| `Vfx.cs` / `DsConfig.cs` | Effect→VFX map and the area/tag/timing constants (timings ported from the Godot front-end). |
| `LogColors.cs` | Maps the engine's `LogLevel` to an NWN talk colour, mirroring the upstream console front-end's palette; used to colour the narrator's spoken lines. |
| `HighScoreStore.cs` | Persists results to JSON under the server plugin-data dir and renders the gravestone description. |

The threading model mirrors `Dungeon-Solitaire.Godot` exactly: the engine blocks
on `RunTurn()`/`SubmitInput`/`AcknowledgeEffect`; we never block Anvil's main
thread, and only read engine collections at points where the engine thread is
provably parked (SelectAlly, secondary choices, paced effect beats, turn-end,
game-over).

### Secondary-choice popup (`ds_choice`)

`InputRequest`s other than the ally/column attack (`SelectCardFromHand`,
`SelectCardFromGraveyard`, `SelectEnemy`, `SelectEffect`, `SelectChoice`) used to
auto-resolve to option 0. They now pop the `ds_choice` conversation. The engine is
parked inside `RequestInput` while this happens, so the request's option lists are
safe to read. `DsSession` builds the option labels, writes them into custom dialog
tokens (`NWScript.SetCustomToken`, IDs 5400–5411 — see `DsConfig.Choice*Token`),
co-locates an invisible session-owned narrator on the player, and starts a private
conversation; `DsManager`'s `ds_chc*`/`ds_chs*`/`ds_chnext`/`ds_chend` handlers gate
slots, submit the pick, page, and detect close. **Abort vs. answered** is told apart
by reference identity: on close, if `GameEngine.PendingInput` is still the *same*
`InputRequest` after `ChoiceReopenDelay`, the player aborted and we re-pop; a real
selection advances the engine to a different request, so no re-pop fires.

### Narration relay (`GameLogger` → narrator talk)

`DungeonSolitaire.Core` narrates the whole game through its static `GameLogger`
(an `Action<LogLevel,string>` that defaults to a no-op — the upstream console
front-end hooks it to colour-print each line). On `Start()`, `DsSession` installs
its own hook and brings the invisible **"The Dungeon"** narrator on stage; each
log line is colour-coded by `LogLevel` (`LogColors.ForLevel`), then `SpeakString`
spoken as normal in-game talk. The hook fires on the engine thread, so lines are
marshalled through the `MainThreadDispatcher` in emission order — they interleave
correctly with the paced VFX/`Board.Sync` beats. `Teardown()` resets the global
hook to a no-op before the narrator is destroyed. Suppressed levels live in
`DsConfig.SuppressedLogLevels` (default `{ Debug, Subtle, ExtraInfo }`; drop the
last two for full console parity).

## Build

```bash
dotnet build csharp/DungeonSolitaire.Nwn -c Release
```

`NWN.Anvil` is pinned to **8193.37.3** in the `.csproj` — bump it to match your
`nwnxee/unified` image's NWN build if needed. `NWN.Core` (**8193.37.4**) is also
referenced, but **compile-only** (`ExcludeAssets="runtime"`): the plugin calls
`NWScript.SetCustomToken` directly, while the Anvil host supplies the assembly at
runtime, so it is not copied to the output.

## Deploy (server runs the `nwndotnet/anvil` container)

1. The server must boot the Anvil managed host. The plain `nwnxee/unified` image
   does **not** ship Anvil — use the `nwndotnet/anvil` image (set in
   `../server.env` as `NWN_IMAGE`, with `NWNX_DOTNET_SKIP=n`). Anvil plugins live
   under `<server-home>/anvil/Plugins/`.
2. Copy the build output into a plugin folder. **The folder name must match the
   main assembly's filename** (`DungeonSolitaire.Nwn`) — Anvil looks for
   `<folder>/<folder>.dll` and silently skips the folder otherwise:
   The destination is **per season** — take `NWN_RUN_DIR` from that season's
   `server.env`, never a hard-coded path, or you deploy to the wrong instance:
   ```bash
   . ../server.env                                    # this repo's season
   DEST="$NWN_RUN_DIR/anvil/Plugins/DungeonSolitaire.Nwn"
   mkdir -p "$DEST"
   cp bin/Release/net8.0/DungeonSolitaire.Nwn.dll  "$DEST"/
   cp bin/Release/net8.0/DungeonSolitaire.Core.dll "$DEST"/
   ```
   `../bin/season-anvil-fix` does all of this (build included) and restarts the
   season. Note the assembly also carries `ServerRestartManager`, so a season
   missing this plugin has no daily restart and no reboot-on-empty — see
   `../season-cutover-guide.md` §5b.
3. Repack the module so the new GFF assets ship in it:
   ```bash
   nwn-manager repack
   ```
   New module resources: `ds_facedown.utp` (statue), `ds_attack.dlg`
   (column-pick conversation), `ds_choice.dlg` (secondary-choice popup), and the
   updated `area017` placeable descriptions. The dialogs' `ds_atk*` / `ds_ch*`
   scripts are handled by the plugin's `[ScriptHandler]` methods — there are no
   `.nss` files for them, and none are needed.
4. Restart that season's server (`systemctl --user restart
   nwn-season-server@<repo-dir-name>.service`) and check
   `podman logs $NWN_CONTAINER_NAME` for:
   ```
   Loading 1 DotNET plugin/s from: "/nwn/run/anvil/Plugins"
   Registered service "DungeonSolitaire.Nwn.ServerRestartManager"
   [DungeonSolitaire] wired Dungeon Solitaire area and lever.
   ```
   `Loading 0` means Anvil skipped the folder — almost always because its name
   doesn't match the assembly (step 2).

## Regenerating the GFF assets

`ds_facedown.utp.json`, `ds_attack.dlg.json`, and `ds_choice.dlg.json` are emitted by:

```bash
python3 csharp/DungeonSolitaire.Nwn/gen_gff.py
```

## Known limitations (vertical slice)

- Card HP is **ratio-mapped** onto each creature's natural blueprint max (so the
  wounded states track the card), not an exact 1:1 — and `OnDamaged` can only
  revert manual damage after the fact (Anvil exposes no damage-cancel), so a hit
  may flash before snapping back.
- Column whittling snaps enemy NPCs forward (no walk) when the front card dies;
  the ally lunge and hand rally are the animated beats.
- Replacing Old-Tagget placeholders (Frodo, Merry, Pippin, Eomer, Lurtz, Grima)
  with bespoke blueprints is future work — see `dungeon-solitaire.txt`.

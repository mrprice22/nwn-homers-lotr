# Custom music, and the jukebox

Two things live here: the **pipeline** that turns an MP3 into a track the
toolset and the server can use, and the **jukebox** item that lets a player
choose one in game.

## Adding a song — the whole job

```
cp "Some Song.mp3" ~/OneDrive/Games/NWNHomersLOTR/music/mp3/
python3 bin/gen-music-tracks.py --apply     # encode + regenerate the tables
bin/build-lotr-music-hak --install          # pack, install, copy to OneDrive
# repack the module, then bin/refresh-nwsync (detached), then restart
```

`gen-music-tracks.py` is dry-run by default — run it with no flags first to see
the resref and row it intends to hand out.

NWSync **is** required here, because the hak set changed. A module-only change
never needs it; this is the other case.

## The file format: a .bmu is an MP3 behind eight bytes

A NWN music resource is an MP3 prefixed with the literal ASCII bytes
`BMU V1.0`. This is settled by the stock files, not by a guide:

```
data/mus/mus_bat_aribeth.bmu  ->  42 4d 55 20 56 31 2e 30  ff fb ...   (MP3 frame)
data/mus/mus_theme_nwn.bmu    ->  42 4d 55 20 56 31 2e 30  49 44 33    (ID3 tag)
```

Either an ID3 tag or a raw frame may follow, so ffmpeg's tags are harmless.

Two traps worth naming, because both produce silence with no error anywhere:

- **The header is case-sensitive.** `BMU v1.0` does not work. This is the usual
  reason a hand-renamed file "just doesn't play".
- **The nwn.wiki "Sounds and Music" page is wrong on this point.** Its table
  says a music file needs no header (only `.wav`-extension sounds do). The
  stock bytes above disagree. Trust the bytes.

Other constraints the generator enforces or warns on:

| Constraint | Why |
|---|---|
| resref ≤ 16 chars | every NWN resource name is |
| 44.1 kHz stereo **CBR** | the engine's music player expects constant bitrate; VBR is the classic cause of a track that loops early or drifts |
| ≤ 15 MB per file | NWSync will not publish a larger one, and says nothing when it skips it |

## Row allocation is append-only, and that matters

Custom tracks occupy `ambientmusic.2da` rows **138+**. Stock is rows 0–137 and
**CEP ships no `ambientmusic.2da`** (verified: `cep2da.hak` contains none), so
nothing sits between stock and us.

An area stores its music as a **row number** in `<area>.git.json` →
`AreaProperties.MusicDay` / `MusicNight` / `MusicBattle` (ints; note this is the
`.git.json`, *not* the `.are.json`). So renumbering a row silently repoints
every area that used it at somebody else's song. Hence:

- **`music/tracks.json` is committed and append-only.** It is the source of
  truth for resref ↔ row. Deleting the MP3 *retires* an entry and leaves its row
  reserved forever; it never gets handed to another track.
- You may hand-edit an entry's `resref` or `name` **before its first hak
  build**. After that it is frozen.

**`hak_music/ambientmusic.stock.2da` is a committed snapshot** of the stock
138-row table, and the generator always builds on that rather than re-extracting
the table at run time. It keeps the build reproducible — the output depends only
on files in this repo — and it forecloses a feedback loop: `nwn_resman_cat
--userdirectory` alone does not load haks (they need `--erfs`), but a run that
did pass `lotr_music.hak` would read **our** table back and append to its own
output, doubling the rows.

## Why music has its own hak

`lotr_music.hak` is separate from `lotr_rules.hak` on purpose. Music is
megabytes and grows with every song; the rules 2DAs are kilobytes and change
rarely. NWSync is content-addressed per file, so folding music into the rules
hak would make every song addition a fresh multi-MB download for every client
even when not one rule changed.

`bin/build-lotr-music-hak --install` also drops a copy at the **OneDrive root**,
next to `lotr_rules.hak` and `lotr_iprp.hak`. That copy is how the Windows
toolset PC gets it — without it the new tracks never appear in the toolset's
area Music dropdown.

Unlike `build-lotr-rules-hak`, the file list here is a **glob**, not a hardcoded
array: a dropped rules 2DA is a real and repeated failure, whereas tracks are
added continuously and `music/tracks.json` is already the authoritative list.
The builder cross-checks the glob against that manifest instead.

## Battle music

Only `mus_bat_`-prefixed resrefs appear in the toolset's **Battle** dropdown, so
`mus_hl_*` tracks show up under Music Day/Night only. That is a toolset filter,
not an engine restriction — a script can set any row into the battle slot, which
is exactly what the jukebox does when it silences battle music. If you ever want
a track selectable as battle music in the toolset, name it `mus_bat_*`.

## The jukebox

Item `jb_jukebox` — base item **29 (miscmedium)**, deliberately non-equippable so
a repeat-use gadget can never get stuck in an equipment slot (see
[CLAUDE-item-appearances.md](CLAUDE-item-appearances.md)). Handed out only by the
Castle Homeless cheat chest (`hm_cheat_chest.nss`, already `Admin_CanChest`-gated).

It carries a Cast Spell: Unique Power property, so activating it raises
`X2_ITEM_EVENT_ACTIVATE` and **X2 tag-based dispatch** runs `jb_jukebox.nss`
purely because the filename matches the tag. `dmfi_activate.nss` is not touched.

| File | Role |
|---|---|
| `jb_tracks.nss` | **generated** track table (count / row / name) |
| `jb_inc.nss` | the logic, the token map, and the paging helpers |
| `jb_conv.dlg.json` | one entry node that loops; 8 track slots per page |
| `jb_show.nss` | builds the menu — a **StartingConditional**, so it runs before the text renders |
| `jb_vis_N` / `jb_sel_N` | per-slot visibility gate and selection action |
| `jb_prev` / `jb_next` / `jb_pgprev` / `jb_pgnext` | paging |
| `jb_ison` / `jb_stopa` | the "Stop the music" option and its action |

Custom tokens **7010–7018** (7010–7017 slot labels, 7018 the status line).
Neighbours: `mw_quiz_inc.nss` 7000–7005, merit 5001–5078, tele 5089–5096.
`SetCustomToken` is module-global, which is why the menu is rebuilt immediately
before the node that reads it and never earlier.

### Track numbering — two functions, two conventions

This is the part that bites, and it bit here. The getter and the setter do **not**
use the same numbering:

```
MusicBackgroundChangeDay(oArea, n)     plays ambientmusic.2da ROW n   (raw row)
MusicBackgroundGetDayTrack(oArea)      returns that row MINUS ONE
```

So a track at row 138 is played by passing **138**, but a snapshot taken with
`Get()` must be **+1'd** before it goes back into `Change()`. `JB_Start` plays
raw and stores incremented; `JB_Stop` hands the stored value straight back.

**Verified in game on 2026-09-11:** the first build passed `row + 1` on the play
path and every pick played the *next* song in the list.

The trap is `dmfi_execute.nss:549-553`, which does `GetDayTrack() + 1` before
calling `ChangeDay()`. That is correct — it is a *restore*, so it is applying the
getter-side adjustment — but it reads at a glance like evidence that `Change()`
is 1-based. It is not. Don't generalise that `+1` to the play path.

### Design decisions that are not accidents

- **Area-wide, not per-player.** `NWNX_Player_MusicBackground*` would give a
  per-listener override, but "the song stays in the room I started it in" is the
  point. Everyone in the area hears it.
- **Not persistent.** State is area local variables, so a reboot restores every
  area's default music. No campaign DB.
- **Snapshot once.** Switching tracks while the jukebox is already on must not
  re-snapshot, or "stop" would restore the previous jukebox pick instead of the
  area's real default. `JB_Start` guards on `JB_ON`.
- **Battle music is silenced** (set to 0) while a track plays and restored on
  stop, so a fight does not cut the song off.

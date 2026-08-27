# Creature respawn audit

**Generated** by `bin/audit-creature-respawn.py` — do not hand-edit; re-run it instead.

Every placed creature instance in `unpacked/*.git.json`, classified by whether its *effective* OnDeath script (the instance's `ScriptDeath` where it overrides the blueprint's) reaches `SE_DoCreatureRespawn()`.

- placed instances: **1004**
- respawn on the standard 900 s timer: **991**
- allowlisted in `tests/respawn_ignore.json`: **13**
- **not respawning and not allowlisted: 0** (`tests/check_creature_respawn.py` fails the repack on these)

## Instance overrides the blueprint's OnDeath

The instance wins at runtime, so fixing only the blueprint changes nothing in game.

| Area | Creature | ResRef | instance OnDeath | kind |
|---|---|---|---|---|
| Angmar Dungeon | Drider Mage | `drowmage003` | `nw_c2_default7` | standard |
| Angmar Dungeon | Drider Mage | `drowmage003` | `nw_c2_default7` | standard |
| Angmar Dungeon | Drider Mage | `drowmage003` | `nw_c2_default7` | standard |
| Angmar Dungeon | Drider Mage | `drowmage003` | `nw_c2_default7` | standard |
| Angmar Dungeon | Drider Mage | `drowmage003` | `nw_c2_default7` | standard |
| Angmar Dungeon | Drider Mage | `drowmage003` | `nw_c2_default7` | standard |

## Respawns, but the blueprint is not in the module

`se_respawn_inc` re-creates from the blueprint resref. These resolve to a base-game/CEP blueprint, so the creature does come back — as the *generic* one, losing every instance override (name, faction, gear).

| Area | Creature | ResRef |
|---|---|---|
| Minas Tirith: Keep | nw_convict | `nw_convict` |
| Esgaroth (Lake Town) | nw_chicken | `nw_chicken` |
| Esgaroth (Lake Town) | nw_chicken | `nw_chicken` |
| Esgaroth (Lake Town) | nw_chicken | `nw_chicken` |
| Esgaroth (Lake Town) | nw_chicken | `nw_chicken` |
| Esgaroth (Lake Town) | nw_chicken | `nw_chicken` |
| Esgaroth (Lake Town) | nw_chicken | `nw_chicken` |
| Barad-Dûr: Barracks | Drow Warrior | `x2_mephdrow009` |
| Barad-Dûr: Keep | nw_drowrogue020 | `nw_drowrogue020` |
| Barn | nw_cow | `nw_cow` |
| Barn | nw_cow | `nw_cow` |
| Barn | nw_cow | `nw_cow` |
| Barn | nw_cow | `nw_cow` |
| Barn | nw_ox | `nw_ox` |
| Barn | nw_ox | `nw_ox` |
| Barn | nw_ox | `nw_ox` |
| Barn | nw_ox | `nw_ox` |
| Bree | nw_cow | `nw_cow` |
| Bree | nw_cow | `nw_cow` |
| Bree | nw_cow | `nw_cow` |
| Bree | nw_cow | `nw_cow` |
| Bree | nw_cow | `nw_cow` |
| Bree | nw_cow | `nw_cow` |
| Bree | nw_cow | `nw_cow` |
| Bree | nw_cow | `nw_cow` |
| Bree | nw_ox | `nw_ox` |
| Bywater | nw_chicken | `nw_chicken` |
| Bywater | nw_chicken | `nw_chicken` |
| Bywater | nw_chicken | `nw_chicken` |
| Bywater | nw_chicken | `nw_chicken` |
| Bywater | nw_chicken | `nw_chicken` |
| Bywater | nw_chicken | `nw_chicken` |
| Bywater | nw_chicken | `nw_chicken` |
| Bywater | nw_chicken | `nw_chicken` |
| Bywater | nw_chicken | `nw_chicken` |
| Bywater | nw_chicken | `nw_chicken` |
| Bywater | zep_cow2 | `zep_cow2` |
| Bywater | zep_cow2 | `zep_cow2` |
| Bywater | zep_cow2 | `zep_cow2` |
| Bywater | zep_cow2 | `zep_cow2` |
| Bywater | zep_cowholsbr | `zep_cowholsbr` |
| Bywater | zep_cowholsbr | `zep_cowholsbr` |
| Great East Road | zep_antelopeb | `zep_antelopeb` |
| Great East Road | zep_antelopeb | `zep_antelopeb` |
| Great East Road | zep_antelopeb | `zep_antelopeb` |
| Great East Road | zep_antelopeb | `zep_antelopeb` |
| Great East Road | zep_antelopeb | `zep_antelopeb` |
| Minas Tirith: Tower of The Arcane | nw_elfmage001 | `nw_elfmage001` |
| Orc Armory | nw_beggmale | `nw_beggmale` |
| Orc Armory | nw_beggmale | `nw_beggmale` |
| Orc Armory | nw_beggmale | `nw_beggmale` |
| Orc Armory | nw_hooker01 | `nw_hooker01` |
| Orc Armory | nw_hooker01 | `nw_hooker01` |
| Orc Armory | nw_hooker02 | `nw_hooker02` |
| Temple of Illuvatar | Elriel Amolebin | `nw_hen_lin_11` |
| Temple of Illuvatar | Nathard Kelten | `nw_humanmerc006` |
| The Pelennor Fields | nw_cow | `nw_cow` |
| The Pelennor Fields | nw_cow | `nw_cow` |
| The Pelennor Fields | nw_cow | `nw_cow` |
| The Pelennor Fields | nw_cow | `nw_cow` |
| The Pelennor Fields | nw_cow | `nw_cow` |
| The Pelennor Fields | nw_cow | `nw_cow` |
| The Pelennor Fields | nw_cow | `nw_cow` |
| The Pelennor Fields | nw_cow | `nw_cow` |
| The Pelennor Fields | nw_cow | `nw_cow` |
| The Pelennor Fields | nw_cow | `nw_cow` |
| The Pelennor Fields | nw_cow | `nw_cow` |
| The Pelennor Fields | nw_cow | `nw_cow` |
| The Pelennor Fields | nw_cow | `nw_cow` |
| The Prancing Pony Ground Floor | Nara Fast Fingers | `nw_halfling005` |
| The Silver Mountains: Pass | A Black Guardian | `nw_golstone` |
| The Temple of Morannon | zep_visagegr | `zep_visagegr` |
| The Temple of Morannon | zep_visagegr | `zep_visagegr` |
| The Temple of Morannon | zep_visagegr | `zep_visagegr` |
| The Valley of Rivendell | Elraniel Teglel'feyn | `nw_elfmage015` |
| Tower of Alatar | Nadriand Apprentice to Alamar | `nw_elfmage005` |
| Minas Tirith: Watchman Defender's Head Quarters | House Guard | `nw_guard` |
| Whitfurrows | nw_chicken | `nw_chicken` |
| Whitfurrows | nw_chicken | `nw_chicken` |
| Whitfurrows | nw_chicken | `nw_chicken` |
| Whitfurrows | nw_chicken | `nw_chicken` |
| Whitfurrows | nw_chicken | `nw_chicken` |
| Whitfurrows | nw_chicken | `nw_chicken` |
| Whitfurrows | nw_chicken | `nw_chicken` |
| Whitfurrows | nw_chicken | `nw_chicken` |
| Whitfurrows | nw_chicken | `nw_chicken` |
| Whitfurrows | nw_cow | `nw_cow` |
| Whitfurrows | nw_cow | `nw_cow` |
| Whitfurrows | nw_cow | `nw_cow` |
| Whitfurrows | nw_dog | `nw_dog` |

## Allowlisted (deliberately never respawn)

| Area | Creature | ResRef | Reason |
|---|---|---|---|
| Carn Dum: Numerok's Den | Ranger of the North | `rangerofthe_2` | corpse prop - OnSpawn 'beatenrider' kills it instantly |
| Appearance Changer and Character Modifying Area | Alignment Adjuster | `lvl_alig_trai002` | unkillable - Plot + Immortal Alignment Adjuster |
| <cÿ}}>House of Homer | Alignment Adjuster | `lvl_alig_trai002` | unkillable - Plot + Immortal Alignment Adjuster |
| <cÿ}}>House of Homer | [SERVER] | `server_npc_2` | unkillable - Plot + Immortal [SERVER] NPC |
| Bree | Combat Dummy | `cbd_dummy` | Combat Dummy: cbd_death runs its own 6-second respawn (see cbd_inc.nss) |
| Carn Dum: Numerok's Den | Dead Girl | `femalekid002_2` | corpse prop - OnSpawn 'beatenrider' kills it instantly |
| Carn Dum: Numerok's Den | Dead Boy | `malekid002_2` | corpse prop - OnSpawn 'beatenrider' kills it instantly |
| Carn Dum: Numerok's Den | Brena | `brena` | corpse prop - OnSpawn 'beatenrider' kills it instantly; hak-only blueprint |
| Kallrist Crypt | Riddle Keeper | `cr_riddlekeep001` | hak-only blueprint - Riddle Keeper puzzle NPC (Kallrist Crypt) |
| Kallrist Crypt | Riddle Keeper | `cr_riddlekeep001` | hak-only blueprint - Riddle Keeper puzzle NPC (Kallrist Crypt) |
| Kallrist Crypt | Riddle Keeper | `cr_riddlekeep001` | hak-only blueprint - Riddle Keeper puzzle NPC (Kallrist Crypt) |
| Númenor:  The Great Forge Of Númenor | Numenorian Armorer | `heavensarmore001` | hak-only blueprint - Numenorian Armorer (utility NPC) |
| 0o Pit Prison o0 | Cyber Jailor | `zep_brownie` | hak-only blueprint - Cyber Jailor (utility NPC) |


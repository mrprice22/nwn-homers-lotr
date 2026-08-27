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

`se_respawn_inc` re-creates from the blueprint resref. With no `.utc.json` here the creature returns as the generic hak creature and every instance override is lost.

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
| Bree | Bill Ferny | `bill` |
| Bree | Bree Farmer | `bree` |
| Bree | Han the Bree Miller | `bree001` |
| Bree | nw_cow | `nw_cow` |
| Bree | nw_cow | `nw_cow` |
| Bree | nw_cow | `nw_cow` |
| Bree | nw_cow | `nw_cow` |
| Bree | nw_cow | `nw_cow` |
| Bree | nw_cow | `nw_cow` |
| Bree | nw_cow | `nw_cow` |
| Bree | nw_cow | `nw_cow` |
| Bree | nw_ox | `nw_ox` |
| Bank of Bree  | Bank Manager | `bankmanager` |
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
| Dol Guldur:  Dark Smith | Dol - Guldur Smithy | `dolguldursmi` |
| Elvalia's Magic Shop | Elvalia | `elvalia` |
| Great East Road | zep_antelopeb | `zep_antelopeb` |
| Great East Road | zep_antelopeb | `zep_antelopeb` |
| Great East Road | zep_antelopeb | `zep_antelopeb` |
| Great East Road | zep_antelopeb | `zep_antelopeb` |
| Great East Road | zep_antelopeb | `zep_antelopeb` |
| Green Dragon Inn | Green Dragon Inn Cook | `greendragoninnco` |
| Gwathdor:  Outskirts | Thayenne Lannen | `thayenne` |
| Kallrist, South shore | A Deck Swabby | `adeckswabby` |
| Kallrist, South shore | A Deck Swabby | `adeckswabby` |
| Kallrist, South shore | A Deck Swabby | `adeckswabby` |
| Kallrist, South shore | A Deck Swabby | `adeckswabby` |
| Kallrist, South shore | Sald Senden | `sald` |
| Kerufall's Lair | A Golden Protector | `shguard001` |
| Kerufall's Lair | A Golden Protector | `shguard001` |
| Kerufall's Lair | A Golden Protector | `shguard001` |
| Kerufall's Lair | A Golden Protector | `shguard001` |
| Kerufall's Lair | A Golden Protector | `shguard001` |
| Kerufall's Lair | A Golden Protector | `shguard001` |
| Kerufall's Lair | A Golden Protector | `shguard001` |
| Last Inn | Tilo the Cook | `breecommoner007` |
| Lowyn's Smithy | Lowyn Galley | `lowyn` |
| Minas Tirith: Tower of The Arcane | nw_elfmage001 | `nw_elfmage001` |
| House of Nazgûl | Portal Slave | `slave` |
| House of Nazgûl | Slave | `slave001` |
| Orc Armory | nw_beggmale | `nw_beggmale` |
| Orc Armory | nw_beggmale | `nw_beggmale` |
| Orc Armory | nw_beggmale | `nw_beggmale` |
| Orc Armory | nw_hooker01 | `nw_hooker01` |
| Orc Armory | nw_hooker01 | `nw_hooker01` |
| Orc Armory | nw_hooker02 | `nw_hooker02` |
| Rivendell | Deloridia Le'dwetholin | `deloridia` |
| Temple of Illuvatar | Elriel Amolebin | `nw_hen_lin_11` |
| Temple of Illuvatar | Nathard Kelten | `nw_humanmerc006` |
| Tharbad Bridge | A Deck Swabby | `adeckswabby` |
| Tharbad Bridge | A Deck Swabby | `adeckswabby` |
| Tharbad Bridge | A Deck Swabby | `adeckswabby` |
| Tharbad Bridge | A Deck Swabby | `adeckswabby` |
| Tharbad Bridge | Tharbad Guard | `luskanite001` |
| Tharbad Bridge | Tharbad Guard | `luskanite001` |
| Tharbad Bridge | A Hungry Refugee | `oldman001` |
| Tharbad Bridge | A Hungry Refugee | `oldman001` |
| Tharbad Bridge | A Hungry Refugee | `oldman001` |
| Tharbad Bridge | A Hungry Refugee | `oldwoman001` |
| Tharbad Bridge | A Hungry Refugee | `oldwoman001` |
| Tharbad Bridge | A Hungry Refugee | `oldwoman001` |
| Tharbad (West) | Tharbad Commoner Human | `breecommoner010` |
| Tharbad (West) | Tharbad Commoner Human | `breecommoner011` |
| Tharbad (West) | Tharbad Commoner Human | `breecommoner013` |
| Tharbad (West) | Tharbad Commoner Human | `breecommoner014` |
| Tharbad (West) | Tharbad Middle Class | `gondorianscri003` |
| Tharbad (West) | Tharbad Middle Class | `gondorianscri004` |
| Tharbad (West) | Tharbad Middle Class | `gondorianscri004` |
| Tharbad (West) | Tharbad Guard | `luskanite001` |
| Tharbad (West) | Tharbad Guard | `luskanite001` |
| Tharbad (West) | Tharbad Guard | `luskanite001` |
| Tharbad (West) | Tharbad Guard | `luskanite001` |
| Tharbad (West) | Tharbad Guard | `luskanite001` |
| Tharbad (West) | Tharbad Guard | `luskanite001` |
| Tharbad (West) | Tharbad Guard | `luskanite001` |
| Tharbad (West) | Tharbad Guard | `luskanite001` |
| Tharbad (West) | Tharbad Guard | `luskanite001` |
| Tharbad (West) | Tharbad Guard | `luskanite001` |
| Tharbad (West) | Tharbad Guard | `luskanite001` |
| Tharbad (East) | Tharbad Commoner Human | `breecommoner010` |
| Tharbad (East) | Tharbad Commoner Human | `breecommoner011` |
| Tharbad (East) | Tharbad Commoner Human | `breecommoner013` |
| Tharbad (East) | Tharbad Commoner Human | `breecommoner014` |
| Tharbad (East) | Tharbad Middle Class | `gondorianscri003` |
| Tharbad (East) | Tharbad Middle Class | `gondorianscri004` |
| Tharbad (East) | Tharbad Guard | `luskanite001` |
| Tharbad (East) | Tharbad Guard | `luskanite001` |
| Tharbad (East) | Tharbad Guard | `luskanite001` |
| Tharbad (East) | Tharbad Guard | `luskanite001` |
| Tharbad (East) | Tharbad Guard | `luskanite001` |
| Tharbad (East) | Tharbad Guard | `luskanite001` |
| The Loft | Vali Leonarna | `vali` |
| The Loft | Mellina Millin | `vali001` |
| The Loft | Trin Welm | `vali002` |
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
| The Prancing Pony Ground Floor | Bree Commoner Human | `breecommoner001` |
| The Prancing Pony Ground Floor | Bree Commoner Human | `breecommoner003` |
| The Prancing Pony Ground Floor | Bree Commoner Human | `breecommoner004` |
| The Prancing Pony Ground Floor | Bree Commoner Human | `breecommoner005` |
| The Prancing Pony Ground Floor | Bree Commoner Hobbit | `breecommoner008` |
| The Prancing Pony Ground Floor | Bree Commoner Hobbit | `breecommoner008` |
| The Prancing Pony Ground Floor | Nara Fast Fingers | `nw_halfling005` |
| The Silver Mountains: Pass | A Black Guardian | `nw_golstone` |
| The Temple of Morannon | zep_visagegr | `zep_visagegr` |
| The Temple of Morannon | zep_visagegr | `zep_visagegr` |
| The Temple of Morannon | zep_visagegr | `zep_visagegr` |
| The Valley of Rivendell | Mebridiel Relein | `mebridiel` |
| The Valley of Rivendell | Elraniel Teglel'feyn | `nw_elfmage015` |
| The Valley of Rivendell | Dryad | `nymph001` |
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


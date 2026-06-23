# Respawn-override validation — tester checklist

We fixed a bug where many named/special NPCs **reverted to a generic version after they died and respawned** (≈15 min). For example, Carn Dum City's *Numanan Numerocks Second Hand* used to come back as *Numarok The Black Hand*, and some hostile bosses came back **friendly**. Each such NPC now has its own blueprint so it respawns exactly as placed.

## How to test each NPC

1. Go to the area and find the NPC. Note its **name**, whether it's **hostile/friendly**, and any visible **gear**.
2. Kill it.
3. Wait for it to respawn (about **15 minutes** real time — a DM can shorten this for a test session).
4. Confirm the respawn is **identical**: same name, same hostility/faction, same equipment. If it comes back with a different (generic) name, wrong hostility, or missing gear, note the NPC + area and report it.

## Headline cases (check these first)

- **Numanan Numerocks Second Hand** — Carn Dum: City. Used to respawn as a different name.
- **Archer Of Mordor** — Morannon - The Black Gate. Hostile NPC that must **not** respawn friendly.

## Full checklist by area

115 named NPCs across 58 areas. Tick each once its respawn matches. (123 total placements were fixed; 8 generic/unnamed ones are omitted here — nothing to eyeball.)

### "Well of Eru"

| ✓ | NPC | Must match on respawn |
|---|-----|-----------------------|
| ☐ | Well-Mart | stats/gear |

### Bank of Bree

| ✓ | NPC | Must match on respawn |
|---|-----|-----------------------|
| ☐ | Banker | stats/gear |

### Brandywine Inn

| ✓ | NPC | Must match on respawn |
|---|-----|-----------------------|
| ☐ | Part Willey | stats/gear |
| ☐ | Perry Blimeaf | stats/gear |

### Brandywine Inn : Second Floor

| ✓ | NPC | Must match on respawn |
|---|-----|-----------------------|
| ☐ | Hobbit, Commoner | name, **faction/hostility** |
| ☐ | Human, Commoner | name |

### Bree

| ✓ | NPC | Must match on respawn |
|---|-----|-----------------------|
| ☐ | Boy | name / identity |
| ☐ | Bree Merchant | name |
| ☐ | Crazy Maggie | name / identity |
| ☐ | Girl | name / identity |
| ☐ | Hanee The Loon | name / identity |
| ☐ | Ranger of the North | **faction/hostility** |

### Carn Dum

| ✓ | NPC | Must match on respawn |
|---|-----|-----------------------|
| ☐ | Black Numenorean Archer | **faction/hostility** |
| ☐ | Black Numenorean Militia | **faction/hostility** |
| ☐ | Elor Desh | **faction/hostility** |

### Carn Dum: City

| ✓ | NPC | Must match on respawn |
|---|-----|-----------------------|
| ☐ | Black Numenorean Mage | **faction/hostility** |
| ☐ | Black Numenorean Militia | **faction/hostility** |
| ☐ | Norfin Thielve'len | **faction/hostility** |
| ☐ | Numanan Numerocks Second Hand | name, **faction/hostility** |

### Carn Dum: Numerok's Den

| ✓ | NPC | Must match on respawn |
|---|-----|-----------------------|
| ☐ | Dead Boy | name / identity |
| ☐ | Dead Girl | name / identity |
| ☐ | Numarok The Black Hand | **faction/hostility** |
| ☐ | Ranger of the North | **faction/hostility** |

### Carn Dum: Smithy

| ✓ | NPC | Must match on respawn |
|---|-----|-----------------------|
| ☐ | Black Numenorean Militia | **faction/hostility** |
| ☐ | Earaldur Rashess | **faction/hostility** |
| ☐ | Unelolas Ellent | **faction/hostility** |

### Carn Dum: Temple

| ✓ | NPC | Must match on respawn |
|---|-----|-----------------------|
| ☐ | Black Numenorean Militia | **faction/hostility** |
| ☐ | Black Numenorean Priestess | stats/gear |
| ☐ | Elvaleng Ma'fer | **faction/hostility** |
| ☐ | Febrith Thient | **faction/hostility** |
| ☐ | Morfiril Cendel | **faction/hostility** |

### Carn Dum: Throne

| ✓ | NPC | Must match on respawn |
|---|-----|-----------------------|
| ☐ | Black Numenorean Militia | **faction/hostility** |
| ☐ | Khamûl The Ringwraith | **faction/hostility** |
| ☐ | Wraith | **faction/hostility** |

### Castle Homeless (Ground Floor)

| ✓ | NPC | Must match on respawn |
|---|-----|-----------------------|
| ☐ | Penguin Merchant | name / identity |

### Dol Guldur City

| ✓ | NPC | Must match on respawn |
|---|-----|-----------------------|
| ☐ | Morgrond Captian of Dol Guldur | stats/gear |

### Dol Guldur:  Tower Of Black Magic Depths

| ✓ | NPC | Must match on respawn |
|---|-----|-----------------------|
| ☐ | The Rancid Skinner Green Mortal of Khamul | **faction/hostility** |

### Esgaroth (Lake Town)

| ✓ | NPC | Must match on respawn |
|---|-----|-----------------------|
| ☐ | White Raxxoon | name / identity |

### Green Dragon Inn

| ✓ | NPC | Must match on respawn |
|---|-----|-----------------------|
| ☐ | Green Dragon Inn Keeper | name / identity |

### Gwathdor:  Outskirts

| ✓ | NPC | Must match on respawn |
|---|-----|-----------------------|
| ☐ | Laxus The Ship Captain | name / identity |

### Helm's Deep

| ✓ | NPC | Must match on respawn |
|---|-----|-----------------------|
| ☐ | Éothain Captian of Helm's Deep | stats/gear |

### Helm's Deep: Keep

| ✓ | NPC | Must match on respawn |
|---|-----|-----------------------|
| ☐ | Eowyn's Personal Guard | name |

### Hidden Port

| ✓ | NPC | Must match on respawn |
|---|-----|-----------------------|
| ☐ | Laxus The Ship Captain | name / identity |

### House of Homer

| ✓ | NPC | Must match on respawn |
|---|-----|-----------------------|
| ☐ | Ping Pong | stats/gear |
| ☐ | [SERVER] | stats/gear |

### House of Nazgûl

| ✓ | NPC | Must match on respawn |
|---|-----|-----------------------|
| ☐ | Nazgûl Watcher | name, **faction/hostility** |

### Kallrist Crypt

| ✓ | NPC | Must match on respawn |
|---|-----|-----------------------|
| ☐ | Fell Beast | stats/gear |

### Kallrist, South shore

| ✓ | NPC | Must match on respawn |
|---|-----|-----------------------|
| ☐ | Andrick Webber | name / identity |

### Lake Town: The Tips Slant Tavern

| ✓ | NPC | Must match on respawn |
|---|-----|-----------------------|
| ☐ | A Drunk Dwarf | name / identity |
| ☐ | A Lake Town Commoner | name / identity |
| ☐ | Crabs the Stinky Cook | name / identity |
| ☐ | Plump Pumpernickle | name / identity |
| ☐ | Ronus Holdorn | name / identity |

### Last Inn

| ✓ | NPC | Must match on respawn |
|---|-----|-----------------------|
| ☐ | Bar Maiden | name / identity |
| ☐ | Bartender | name / identity |

### Lonely Mountain: Main Hall

| ✓ | NPC | Must match on respawn |
|---|-----|-----------------------|
| ☐ | A Dwarf Ajudicator | name |

### Lothlorien: Flets

| ✓ | NPC | Must match on respawn |
|---|-----|-----------------------|
| ☐ | Greater Elven Watcher | stats/gear |

### Lothlorien: North

| ✓ | NPC | Must match on respawn |
|---|-----|-----------------------|
| ☐ | Greater Elven Watcher | stats/gear |

### Mad Eye Moody's Store

| ✓ | NPC | Must match on respawn |
|---|-----|-----------------------|
| ☐ | Mad Eye Moody | name / identity |

### Minas Tirith: Temple

| ✓ | NPC | Must match on respawn |
|---|-----|-----------------------|
| ☐ | High Priest of Gondor | stats/gear |

### Minas Tirith: Watchman Defender's Head Quarters

| ✓ | NPC | Must match on respawn |
|---|-----|-----------------------|
| ☐ | Gondorian Bowman | stats/gear |
| ☐ | Gondorian Guardsman | stats/gear |

### Mirkwood: Dol Guldur

| ✓ | NPC | Must match on respawn |
|---|-----|-----------------------|
| ☐ | Dol Guldur Gate Keeper | stats/gear |
| ☐ | Shadow Lord of Dol Guldur | stats/gear |

### Mirkwood: Thranduil's Hall

| ✓ | NPC | Must match on respawn |
|---|-----|-----------------------|
| ☐ | Nature's Defender | **faction/hostility** |
| ☐ | Thranduil, King of Eryn Lasgalen | **faction/hostility** |

### Morannon - The Black Gate

| ✓ | NPC | Must match on respawn |
|---|-----|-----------------------|
| ☐ | Archer Of Mordor | **faction/hostility** |
| ☐ | Gate Axeman | **faction/hostility** |
| ☐ | Gate Giant | **faction/hostility** |
| ☐ | Gate Shaman - Mordor Black Gate | **faction/hostility** |
| ☐ | Orc Sorcerer | **faction/hostility** |
| ☐ | Temple Mistress | **faction/hostility** |
| ☐ | Thragg, Gate Commander | **faction/hostility** |

### Mount Doom: Halls of Sauron

| ✓ | NPC | Must match on respawn |
|---|-----|-----------------------|
| ☐ | Sauron's Personal Gaurds | name |

### Mount Gundabad

| ✓ | NPC | Must match on respawn |
|---|-----|-----------------------|
| ☐ | Black Numenorean Militia | stats/gear |
| ☐ | Black Numenorean Priestess | **faction/hostility** |
| ☐ | Black Numenorean Shadow Master | **faction/hostility** |

### Mount Gundabad Level 2

| ✓ | NPC | Must match on respawn |
|---|-----|-----------------------|
| ☐ | Black Numenorean Militia | stats/gear |
| ☐ | Black Numenorean Priestess | **faction/hostility** |
| ☐ | Black Numenorean Shadow Master | **faction/hostility** |

### Orc Armory

| ✓ | NPC | Must match on respawn |
|---|-----|-----------------------|
| ☐ | Deekin the General | stats/gear |

### Ranger Waystation

| ✓ | NPC | Must match on respawn |
|---|-----|-----------------------|
| ☐ | Goriolad Wende'lyn | stats/gear |

### Rhosgobel:  Tower

| ✓ | NPC | Must match on respawn |
|---|-----|-----------------------|
| ☐ | Radagast the Brown | stats/gear |

### Rivendell Upper Halls

| ✓ | NPC | Must match on respawn |
|---|-----|-----------------------|
| ☐ | Elrond | stats/gear |

### Taggets Smith Shop

| ✓ | NPC | Must match on respawn |
|---|-----|-----------------------|
| ☐ | Old Tagget | name / identity |
| ☐ | Tagget's Lacky | name / identity |

### Temple of Marr

| ✓ | NPC | Must match on respawn |
|---|-----|-----------------------|
| ☐ | A Dwarf Ajudicator | name |

### Tharbad (East)

| ✓ | NPC | Must match on respawn |
|---|-----|-----------------------|
| ☐ | Dona Blake | name / identity |

### Tharbad (West)

| ✓ | NPC | Must match on respawn |
|---|-----|-----------------------|
| ☐ | Betta Arner | name / identity |
| ☐ | Keeper of The Peace | stats/gear |
| ☐ | Tonan Sensen | name / identity |

### Tharbad Bridge

| ✓ | NPC | Must match on respawn |
|---|-----|-----------------------|
| ☐ | A Hungry Refugee | name / identity |
| ☐ | Andrick Webber | name / identity |

### The Halls of Truth

| ✓ | NPC | Must match on respawn |
|---|-----|-----------------------|
| ☐ | A Dwarf Ajudicator | name |
| ☐ | Dellinth the Advocet | stats/gear |
| ☐ | Gimli | stats/gear |

### The House of Healing

| ✓ | NPC | Must match on respawn |
|---|-----|-----------------------|
| ☐ | Card Mennard | **faction/hostility** |
| ☐ | Kashan Brino | stats/gear |
| ☐ | Zachal Aylomen | stats/gear |

### The Prancing Pony Ground Floor

| ✓ | NPC | Must match on respawn |
|---|-----|-----------------------|
| ☐ | Bar Maiden | name / identity |
| ☐ | Barliman Butterbur | name / identity |
| ☐ | Bartender | name / identity |

### The Secret Pass of Mordor

| ✓ | NPC | Must match on respawn |
|---|-----|-----------------------|
| ☐ | Mordor Orc Scout Soldier | name |

### The Smithy of Rivendell

| ✓ | NPC | Must match on respawn |
|---|-----|-----------------------|
| ☐ | Elrebrier Yanicen | name / identity |
| ☐ | Thrulith Xilow | name / identity |

### Tower of Alatar

| ✓ | NPC | Must match on respawn |
|---|-----|-----------------------|
| ☐ | Alatar the Blue | stats/gear |

### Tower of Orthanc

| ✓ | NPC | Must match on respawn |
|---|-----|-----------------------|
| ☐ | Dunland Shaman | stats/gear |
| ☐ | Uruk Hai White Hand's Chosen | stats/gear |

### Tower of the High Wizard: Ground Floor

| ✓ | NPC | Must match on respawn |
|---|-----|-----------------------|
| ☐ | Epic Gondorian Guardsman | stats/gear |
| ☐ | Gondorian Wizard | stats/gear |

### Tower of the High Wizard: The High Wizard's Chamber

| ✓ | NPC | Must match on respawn |
|---|-----|-----------------------|
| ☐ | High Wizard of Gondor | stats/gear |

### Tower of the High Wizard: The Library

| ✓ | NPC | Must match on respawn |
|---|-----|-----------------------|
| ☐ | Epic Gondorian Guardsman | stats/gear |

### Whitfurrow Inn

| ✓ | NPC | Must match on respawn |
|---|-----|-----------------------|
| ☐ | Rigrin Took | stats/gear |

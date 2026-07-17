// q_dwd_inc.nss -- Dwarven Defender initiation "The Unbroken Stone"
// (roadmap: dwarven-defender-quest)
//
// The tenth of the twelve prestige-order quests hung on Halmir the Grey
// (the prestige hub, prsg_inc.nss). Compact one-off, journal tag
// "pc_dwarvendefender".
//
// Flow: Halmir's Dwarven Defenders branch (prsg_conv) offers the stand to
// a PC with 1+ Dwarven Defender level who is of Durin's folk
// (CLASS_TYPE_DWARVEN_DEFENDER = 36 and RACIAL_TYPE_DWARF = 0, both
// verified in ovr/nwscript.nss -- the class is dwarf-only in NWN anyway,
// but the race check is kept defensively per the roadmap item; the hub
// line itself is already race+level gated by the existing prsg_c_dwdef /
// PRSG_QualifiesDwarvenDef, L14+ dwarves only). The trial: in Balin's
// Tomb in Moria stands the headstone "Here lies Balin, son of Fundin,
// Lord of Moria" (existing placed instance 86 in balinstomb.git.json --
// already usable + plot with no scripts; retagged DwdBalinStone, its
// OnUsed now runs q_dwd_stone; no script referenced the generic old tag
// "Headstone", and the sibling shadowdancer quest's hook in the same area
// is the DeepWell, instance 52 -- untouched). Stand at the tomb as
// Balin's guard stood: come clad in the war-weight of Khazad -- heavy
// armor, base AC 6 or more (splint / half-plate / full plate) -- and use
// the stone. QDWD_IsStoneClad reads the armor's BASE AC from
// parts_chest.2da via the torso model (the module's established idiom,
// zep_cr_canca.nss), so enhancement bonuses on light armor cannot fake
// the weight. Leathers, robes or a bare chest fail with a flavor
// message, nothing granted, retry allowed. Deterministic: no dice. Carry
// the shard the stone gives back to Halmir; the induction consumes it
// and awards the Warhelm of Durin's Watch plus XP.
//
// Quest state is per-character and persistent via the prestige hub's
// campaign-DB stage idiom (prestigedb, order key "dwdef" -- see
// prsg_inc.nss): 0 none / 1 accepted / 2 shard in hand / 3 done.
// One-off: stage 3 never resets. If the shard is somehow lost at stage
// 2, keeping the stand again re-gives it (graceful, not farmable: the
// item is plot + cursed and only the finish consumes it).
//
// No new placements and no admin waypoint: the headstone already stands
// in Balin's Tomb (placed instance 86 in balinstomb.git.json).

#include "prsg_inc"

const string QDWD_ORDER     = "dwdef";               // prestigedb stage key
const string QDWD_QUEST     = "pc_dwarvendefender";  // journal category tag
const string QDWD_SHARD_RES = "q_dwd_shard";         // reagent blueprint
const string QDWD_SHARD_TAG = "UnbrokenShard";
const string QDWD_HELM_RES  = "q_dwd_helm";          // reward blueprint
const string QDWD_HELM_TAG  = "DurinsWatchHelm";

const int QDWD_XP = 1000;  // induction XP (L14-tier order)

// Heavy armor threshold: base AC 6+ is splint mail / half-plate / full
// plate (banded also lands at 6 -- war-weight either way).
const int QDWD_HEAVY_AC = 6;

// Stages (see header).
const int QDWD_STAGE_NONE     = 0;
const int QDWD_STAGE_ACCEPTED = 1;
const int QDWD_STAGE_SHARD    = 2;
const int QDWD_STAGE_DONE     = 3;

int QDWD_GetStage(object oPC)
{
    return PRSG_GetStage(oPC, QDWD_ORDER);
}

void QDWD_SetStage(object oPC, int nStage)
{
    PRSG_SetStage(oPC, QDWD_ORDER, nStage);
}

// TRUE if oPC has already taken the Defender's stand (1+ Dwarven
// Defender level, CLASS_TYPE_DWARVEN_DEFENDER = 36) AND is of Durin's
// folk (RACIAL_TYPE_DWARF = 0) -- the design gate. The race clause is
// defensive: the class is dwarf-only in NWN, but the roadmap item asks
// for dwarves only, so both are checked.
int QDWD_IsDwarvenDefender(object oPC)
{
    return PRSG_HasClass(oPC, CLASS_TYPE_DWARVEN_DEFENDER)
        && GetRacialType(oPC) == RACIAL_TYPE_DWARF;
}

// The turn-in reagent check: does oPC carry the shard?
int QDWD_HasShard(object oPC)
{
    return GetIsObjectValid(GetItemPossessedBy(oPC, QDWD_SHARD_TAG));
}

// The war-weight condition: TRUE while oPC wears heavy armor -- a chest
// item whose BASE armor class (parts_chest.2da ACBONUS for the torso
// model, the module's established base-AC idiom from zep_cr_canca.nss)
// is QDWD_HEAVY_AC or more: splint / banded / half-plate / full plate.
// Reading the 2DA instead of GetItemACValue means enchantment bonuses on
// leathers cannot fake the weight; a CEP torso model beyond the 2DA
// range reads as 0 and fails (retry in standard heavy iron).
// Deterministic, no dice.
int QDWD_IsStoneClad(object oPC)
{
    object oChest = GetItemInSlot(INVENTORY_SLOT_CHEST, oPC);
    if (!GetIsObjectValid(oChest)) return FALSE;
    if (GetBaseItemType(oChest) != BASE_ITEM_ARMOR) return FALSE;

    int nBaseAC = StringToInt(Get2DAString("parts_chest", "ACBONUS",
        GetItemAppearance(oChest, ITEM_APPR_TYPE_ARMOR_MODEL,
                          ITEM_APPR_ARMOR_MODEL_TORSO)));
    return nBaseAC >= QDWD_HEAVY_AC;
}

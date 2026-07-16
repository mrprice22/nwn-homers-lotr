// q_dvc_inc.nss -- Divine Champion initiation "The Shield of Others"
// (roadmap: divine-champion-quest)
//
// The ninth of the twelve prestige-order quests hung on Halmir the Grey
// (the prestige hub, prsg_inc.nss). Compact one-off, journal tag
// "pc_divinechampion".
//
// Flow: Halmir's Divine Champions branch (prsg_conv) offers the vigil to
// a PC with 1+ Divine Champion level (CLASS_TYPE_DIVINE_CHAMPION = 32,
// verified in ovr/nwscript.nss -- the design gate; the hub line itself is
// visible from total level 14, existing prsg_c_divch). The trial: in the
// temple of Minas Tirith stands the Altar of the Istari (existing placed
// instance 0 in minastirithtemp.git.json -- already usable + plot with no
// scripts; retagged DvcVigilAltar, its OnUsed now runs q_dvc_altar; no
// code referenced the old tag "AltarShrineGood"). Keep the vigil as the
// order keeps it: use the altar with a shield borne on the off-hand
// (QDVC_IsShieldBorne -- GetItemInSlot(INVENTORY_SLOT_LEFTHAND) is a
// small/large/tower shield, BASE_ITEM_SMALLSHIELD 14 / LARGESHIELD 56 /
// TOWERSHIELD 57, all verified in ovr/nwscript.nss), because the
// champion's vow is not to strike harder but to stand between. A bare arm
// or a second blade where the shield should ride fails with a flavor
// message, nothing granted, retry allowed. Deterministic: no dice. Carry
// the oath-light the vigil kindles back to Halmir; the induction consumes
// it and awards the Mantle of the Westward Vow plus XP.
//
// Quest state is per-character and persistent via the prestige hub's
// campaign-DB stage idiom (prestigedb, order key "divch" -- see
// prsg_inc.nss): 0 none / 1 accepted / 2 oath-light in hand / 3 done.
// One-off: stage 3 never resets. If the light is somehow lost at stage 2,
// keeping the vigil again re-gives it (graceful, not farmable: the item
// is plot + cursed and only the finish consumes it).
//
// No new placements and no admin waypoint: the altar already stands in
// the Minas Tirith temple (placed instance 0 in minastirithtemp.git.json).

#include "prsg_inc"

const string QDVC_ORDER     = "divch";              // prestigedb stage key
const string QDVC_QUEST     = "pc_divinechampion";  // journal category tag
const string QDVC_LIGHT_RES = "q_dvc_light";        // reagent blueprint
const string QDVC_LIGHT_TAG = "OathLight";
const string QDVC_CLOAK_RES = "q_dvc_mantle";       // reward blueprint
const string QDVC_CLOAK_TAG = "WestwardMantle";

const int QDVC_XP = 1000;  // induction XP (L14-tier order)

// Stages (see header).
const int QDVC_STAGE_NONE     = 0;
const int QDVC_STAGE_ACCEPTED = 1;
const int QDVC_STAGE_LIGHT    = 2;
const int QDVC_STAGE_DONE     = 3;

int QDVC_GetStage(object oPC)
{
    return PRSG_GetStage(oPC, QDVC_ORDER);
}

void QDVC_SetStage(object oPC, int nStage)
{
    PRSG_SetStage(oPC, QDVC_ORDER, nStage);
}

// TRUE if oPC's sword is already vowed (1+ Divine Champion level) -- the
// design gate for the vigil.
int QDVC_IsDivineChampion(object oPC)
{
    return PRSG_HasClass(oPC, CLASS_TYPE_DIVINE_CHAMPION);
}

// The turn-in reagent check: does oPC carry the oath-light?
int QDVC_HasLight(object oPC)
{
    return GetIsObjectValid(GetItemPossessedBy(oPC, QDVC_LIGHT_TAG));
}

// The stand-between condition: TRUE while oPC bears a shield on the
// off-hand arm -- small, large or tower (BASE_ITEM_SMALLSHIELD = 14,
// BASE_ITEM_LARGESHIELD = 56, BASE_ITEM_TOWERSHIELD = 57, verified in
// ovr/nwscript.nss). Deterministic, no dice: a champion with shield borne
// always passes; a bare arm, a second blade, a torch never do.
int QDVC_IsShieldBorne(object oPC)
{
    object oOff = GetItemInSlot(INVENTORY_SLOT_LEFTHAND, oPC);
    if (!GetIsObjectValid(oOff)) return FALSE;

    int nBase = GetBaseItemType(oOff);
    return nBase == BASE_ITEM_SMALLSHIELD
        || nBase == BASE_ITEM_LARGESHIELD
        || nBase == BASE_ITEM_TOWERSHIELD;
}

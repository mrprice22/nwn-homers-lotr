// q_wpm_inc.nss -- Weapon Master initiation "The Sworn Blade"
// (roadmap: weapon-master-quest)
//
// The eighth of the twelve prestige-order quests hung on Halmir the Grey
// (the prestige hub, prsg_inc.nss). Compact one-off, journal tag
// "pc_weaponmaster".
//
// Flow: Halmir's Weapon Masters branch (prsg_conv) offers the trial to a
// PC with 1+ Weapon Master level (CLASS_TYPE_WEAPON_MASTER = 33, verified
// in ovr/nwscript.nss -- the design gate; the hub line itself is visible
// from total level 13, existing prsg_c_wm). The trial: below the walls of
// Minas Tirith the Guard keeps its training row -- three scarred practice
// posts (existing Combat Dummy placeables in minastirith.git.json; the
// first instance is reused -- retagged WMTrialPost, made usable, its
// OnUsed now runs q_wpm_dummy; it had no previous scripts and no code
// referenced the old shared "Combat Dummy" tag). Strike the post with the
// weapon your soul is sworn to: the main-hand weapon must be one whose
// Weapon of Choice feat the PC actually has (QWPM_IsSwornBlade --
// baseitems.2da column "WeaponOfChoiceFeat" via Get2DAString, feat checked
// with GetHasFeat; every Weapon Master has Weapon of Choice in exactly the
// weapons they mastered, and ranged/exotic non-WoC rows are **** in the
// 2da so they read as empty and fail). Bare hands or a borrowed blade fail
// with a flavor message, nothing granted, retry allowed. Deterministic:
// no dice. Carry the notch the cut frees from the post back to Halmir;
// the induction consumes it and awards the Buckle of the Sworn Blade
// plus XP.
//
// Quest state is per-character and persistent via the prestige hub's
// campaign-DB stage idiom (prestigedb, order key "wm" -- see
// prsg_inc.nss): 0 none / 1 accepted / 2 notch in hand / 3 done.
// One-off: stage 3 never resets. If the notch is somehow lost at stage 2,
// striking the post again re-gives it (graceful, not farmable: the item
// is plot + cursed and only the finish consumes it).
//
// No new placements and no admin waypoint: the practice post already
// stands in Minas Tirith (placed instance 6 of blueprint plc_cmbtdummy in
// minastirith.git.json).

#include "prsg_inc"

const string QWPM_ORDER     = "wm";               // prestigedb stage key
const string QWPM_QUEST     = "pc_weaponmaster";  // journal category tag
const string QWPM_NOTCH_RES = "q_wpm_notch";      // reagent blueprint
const string QWPM_NOTCH_TAG = "ProvenNotch";
const string QWPM_BELT_RES  = "q_wpm_belt";       // reward blueprint
const string QWPM_BELT_TAG  = "SwornBladeBuckle";

const int QWPM_XP = 1000;  // induction XP (L13-tier order)

// Stages (see header).
const int QWPM_STAGE_NONE     = 0;
const int QWPM_STAGE_ACCEPTED = 1;
const int QWPM_STAGE_NOTCH    = 2;
const int QWPM_STAGE_DONE     = 3;

int QWPM_GetStage(object oPC)
{
    return PRSG_GetStage(oPC, QWPM_ORDER);
}

void QWPM_SetStage(object oPC, int nStage)
{
    PRSG_SetStage(oPC, QWPM_ORDER, nStage);
}

// TRUE if oPC's hand is already sworn (1+ Weapon Master level) -- the
// design gate for the trial.
int QWPM_IsWeaponMaster(object oPC)
{
    return PRSG_HasClass(oPC, CLASS_TYPE_WEAPON_MASTER);
}

// The turn-in reagent check: does oPC carry the notch?
int QWPM_HasNotch(object oPC)
{
    return GetIsObjectValid(GetItemPossessedBy(oPC, QWPM_NOTCH_TAG));
}

// The Weapon of Choice feat for oItem's base type, or -1 when none exists
// (empty main hand, ranged weapons, armor, torches... -- every row that is
// **** in baseitems.2da's WeaponOfChoiceFeat column reads back as "" from
// Get2DAString). Column name verified against the game's baseitems.2da.
int QWPM_SwornWeaponFeat(object oItem)
{
    if (!GetIsObjectValid(oItem)) return -1;

    string sFeat = Get2DAString("baseitems", "WeaponOfChoiceFeat",
                                GetBaseItemType(oItem));
    if (sFeat == "") return -1;

    return StringToInt(sFeat);
}

// The one-blade-one-life condition: TRUE while oPC's main hand holds a
// weapon whose Weapon of Choice feat they actually have -- the weapon
// their soul is sworn to. Deterministic, no dice: a Weapon Master with
// their chosen blade drawn always passes; bare hands, a borrowed blade or
// a bow never do.
int QWPM_IsSwornBlade(object oPC)
{
    int nFeat = QWPM_SwornWeaponFeat(
        GetItemInSlot(INVENTORY_SLOT_RIGHTHAND, oPC));
    return nFeat >= 0 && GetHasFeat(nFeat, oPC);
}

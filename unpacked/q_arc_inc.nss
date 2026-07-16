// q_arc_inc.nss -- Arcane Archer initiation "The Warden's Mark"
// (roadmap: arcane-archer-quest)
//
// The fifth of the twelve prestige-order quests hung on Halmir the Grey
// (the prestige hub, prsg_inc.nss). Compact one-off, journal tag
// "pc_arcanearcher".
//
// Flow: Halmir's Arcane Archers branch (prsg_conv) offers the trial to a
// PC with 1+ Arcane Archer level (CLASS_TYPE_ARCANE_ARCHER = 29, verified
// in ovr/nwscript.nss -- the design gate; the hub line itself is visible
// from total level 12). The trial: on the proving ground of Rivendell
// stands a target older than the house around it, and in it a
// grey-fletched shaft a warden of the Galadhrim loosed in an elder year.
// The mark yields the shaft only to a hand that comes as an archer comes:
// BOW IN HAND, ARROW NOCKED -- a longbow or shortbow equipped and arrows
// in the quiver. Come any other way and the trial fails that attempt
// (flavor message, nothing granted, retry allowed); come as an archer and
// the old mark gives up the Warden's Shaft (q_arc_shaft, plot + cursed).
// Carry it back to Halmir; the induction awards the Bracers of the Grey
// Fletching plus XP and consumes the shaft.
//
// Quest state is per-character and persistent via the prestige hub's
// campaign-DB stage idiom (prestigedb, order key "archer" -- see
// prsg_inc.nss): 0 none / 1 accepted / 2 shaft in hand / 3 done.
// One-off: stage 3 never resets. If the shaft is somehow lost at stage 2,
// drawing at the mark again re-gives it (graceful, not farmable: the item
// is plot + cursed and the finish consumes it from stage 2 only).
//
// No new placements and no admin waypoint: the target already stands on
// Rivendell's training ground (existing placed instance in
// rivendell.git.json, reused -- retagged WardenMark, made usable, its
// instance OnUsed now runs q_arc_target; it had no previous OnUsed).

#include "prsg_inc"

const string QARC_ORDER      = "archer";          // prestigedb stage key
const string QARC_QUEST      = "pc_arcanearcher"; // journal category tag
const string QARC_SHAFT_RES  = "q_arc_shaft";     // reagent blueprint
const string QARC_SHAFT_TAG  = "WardenShaft";
const string QARC_BRACER_RES = "q_arc_bracer";    // reward blueprint
const string QARC_BRACER_TAG = "GreyFletchBracer";

const int QARC_XP = 1000;  // induction XP (L12-tier order)

// Stages (see header).
const int QARC_STAGE_NONE     = 0;
const int QARC_STAGE_ACCEPTED = 1;
const int QARC_STAGE_SHAFT    = 2;
const int QARC_STAGE_DONE     = 3;

int QARC_GetStage(object oPC)
{
    return PRSG_GetStage(oPC, QARC_ORDER);
}

void QARC_SetStage(object oPC, int nStage)
{
    PRSG_SetStage(oPC, QARC_ORDER, nStage);
}

// TRUE if oPC has already bent the bow to the art (1+ Arcane Archer
// level) -- the design gate for the trial.
int QARC_IsArcher(object oPC)
{
    return PRSG_HasClass(oPC, CLASS_TYPE_ARCANE_ARCHER);
}

// The turn-in reagent check: does oPC carry the shaft?
int QARC_HasShaft(object oPC)
{
    return GetIsObjectValid(GetItemPossessedBy(oPC, QARC_SHAFT_TAG));
}

// The come-as-an-archer condition: TRUE only with a longbow or shortbow
// equipped in the weapon hand AND arrows in the quiver slot -- "bow in
// hand, arrow nocked". Crossbows and slings are not the Galadhrim's art;
// an empty quiver is an empty promise. Deterministic (no dice), so the
// trial is retry-friendly: equip properly and use the mark again.
int QARC_ComesAsArcher(object oPC)
{
    object oBow = GetItemInSlot(INVENTORY_SLOT_RIGHTHAND, oPC);
    if (!GetIsObjectValid(oBow)) return FALSE;

    int nBase = GetBaseItemType(oBow);
    if (nBase != BASE_ITEM_LONGBOW && nBase != BASE_ITEM_SHORTBOW)
        return FALSE;

    return GetIsObjectValid(GetItemInSlot(INVENTORY_SLOT_ARROWS, oPC));
}

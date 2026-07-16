// q_asn_inc.nss -- Assassin initiation "The Quiet Knives"
// (roadmap: assassin-quest)
//
// The seventh of the twelve prestige-order quests hung on Halmir the Grey
// (the prestige hub, prsg_inc.nss). Compact one-off, journal tag
// "pc_assassin".
//
// Flow: Halmir's Assassins branch (prsg_conv) offers the trial to a PC
// with 1+ Assassin level (CLASS_TYPE_ASSASSIN = 30, verified in
// ovr/nwscript.nss -- the design gate; the hub line itself is visible
// from total level 13, existing prsg_c_assn). The trial is not a killing:
// a sealed writ has been left at one of the order's dead drops -- the old
// wine barrel standing against the houses of Bree (existing placed
// instance in bree.git.json, reused -- retagged AsnDeadDrop, its OnOpen
// now runs q_asn_drop; it had no previous OnOpen/OnUsed, so there is
// nothing to chain, and it is Plot so it cannot be bashed away). The drop
// yields the writ only to a hand no eye marks: open the barrel while NOT
// in stealth mode (QASN_IsUnseen, GetActionMode/ACTION_MODE_STEALTH --
// both verified in ovr/nwscript.nss) and the attempt fails with a flavor
// message, nothing granted, retry allowed -- slip into shadow and reach
// again. Deterministic: no dice. Carry the writ back to Halmir sealed;
// the induction burns it (the name inside is the PC's own), awards the
// Gloves of the Quiet Hand plus XP.
//
// Quest state is per-character and persistent via the prestige hub's
// campaign-DB stage idiom (prestigedb, order key "assn" -- see
// prsg_inc.nss): 0 none / 1 accepted / 2 writ in hand / 3 done.
// One-off: stage 3 never resets. If the writ is somehow lost at stage 2,
// lifting at the drop again re-gives it (graceful, not farmable: the item
// is plot + cursed and only the finish consumes it).
//
// No new placements and no admin waypoint: the wine barrel already stands
// in Bree (placed instance 112 of blueprint barrel001 in bree.git.json;
// the old shared tag "WineBarrel" was referenced by no script).

#include "prsg_inc"

const string QASN_ORDER      = "assn";           // prestigedb stage key
const string QASN_QUEST      = "pc_assassin";    // journal category tag
const string QASN_WRIT_RES   = "q_asn_writ";     // reagent blueprint
const string QASN_WRIT_TAG   = "SealedWrit";
const string QASN_GLOVES_RES = "q_asn_gloves";   // reward blueprint
const string QASN_GLOVES_TAG = "QuietHandGloves";

const int QASN_XP = 1000;  // induction XP (L13-tier order)

// Stages (see header).
const int QASN_STAGE_NONE     = 0;
const int QASN_STAGE_ACCEPTED = 1;
const int QASN_STAGE_WRIT     = 2;
const int QASN_STAGE_DONE     = 3;

int QASN_GetStage(object oPC)
{
    return PRSG_GetStage(oPC, QASN_ORDER);
}

void QASN_SetStage(object oPC, int nStage)
{
    PRSG_SetStage(oPC, QASN_ORDER, nStage);
}

// TRUE if oPC already walks with the quiet knives (1+ Assassin level) --
// the design gate for the trial.
int QASN_IsAssassin(object oPC)
{
    return PRSG_HasClass(oPC, CLASS_TYPE_ASSASSIN);
}

// The turn-in reagent check: does oPC carry the writ?
int QASN_HasWrit(object oPC)
{
    return GetIsObjectValid(GetItemPossessedBy(oPC, QASN_WRIT_TAG));
}

// The no-eye-marks-the-hand condition: TRUE while oPC moves in stealth
// mode (the toggled mode, GetActionMode -- deterministic, no dice; no
// skill roll is made, so even a first-level Assassin who remembers to
// walk in shadow passes, and a legend who forgets does not).
int QASN_IsUnseen(object oPC)
{
    return GetActionMode(oPC, ACTION_MODE_STEALTH);
}

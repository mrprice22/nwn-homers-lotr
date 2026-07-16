// q_pal_inc.nss -- Pale Master initiation "The Twenty-First Tomb"
// (roadmap: pale-master-quest)
//
// The third of the twelve prestige-order quests hung on Halmir the Grey
// (the prestige hub, prsg_inc.nss). Compact one-off, journal tag
// "pc_palemaster".
//
// Flow: Halmir's Pale-Masters branch (prsg_conv) offers the rite to a PC
// with 1+ Pale Master level (CLASS_TYPE_PALE_MASTER = 34, verified in
// ovr/nwscript.nss -- the design gate; the hub line itself is visible
// from total level 11). The errand: beneath the Bree Crypt lies a lower
// vault; among its named tombs one sarcophagus carries no name -- the
// twenty-first tomb. Open it with your own hands (an EXISTING placed
// sarcophagus instance in breecryptlowerle, reused -- its instance
// OnOpen now runs q_pal_tomb, which chains the instance's previous
// treasure script nw_o2_classhig), take the pale grave-dust within
// (q_pal_dust, plot + cursed), and carry it back unspilled. The turn-in
// is the design card's GetItemPossessedBy reagent check; the induction
// awards the Talisman of the Twenty-First Tomb plus XP and consumes the
// dust.
//
// Quest state is per-character and persistent via the prestige hub's
// campaign-DB stage idiom (prestigedb, order key "pale" -- see
// prsg_inc.nss): 0 none / 1 accepted / 2 dust in hand / 3 done.
// One-off: stage 3 never resets. If the dust is somehow lost at stage 2,
// opening the tomb again re-gives it (graceful, not farmable: the item
// is plot + cursed and the finish consumes it from stage 2 only).
//
// No new placements and no admin waypoint: the sarcophagus already
// stands in the lower vault, so nothing is script-spawned.

#include "prsg_inc"

const string QPAL_ORDER    = "pale";            // prestigedb stage key
const string QPAL_QUEST    = "pc_palemaster";   // journal category tag
const string QPAL_DUST_RES = "q_pal_dust";      // reagent blueprint
const string QPAL_DUST_TAG = "PaleGraveDust";
const string QPAL_TAL_RES  = "q_pal_talis";     // reward blueprint
const string QPAL_TAL_TAG  = "Talisman21Tomb";

const int QPAL_XP = 1000;  // induction XP (L11-tier order)

// Stages (see header).
const int QPAL_STAGE_NONE     = 0;
const int QPAL_STAGE_ACCEPTED = 1;
const int QPAL_STAGE_DUST     = 2;
const int QPAL_STAGE_DONE     = 3;

int QPAL_GetStage(object oPC)
{
    return PRSG_GetStage(oPC, QPAL_ORDER);
}

void QPAL_SetStage(object oPC, int nStage)
{
    PRSG_SetStage(oPC, QPAL_ORDER, nStage);
}

// TRUE if oPC already reads the pale page (1+ Pale Master level) -- the
// design gate for the rite.
int QPAL_IsPale(object oPC)
{
    return PRSG_HasClass(oPC, CLASS_TYPE_PALE_MASTER);
}

// The design card's reagent check: does oPC carry the grave-dust?
int QPAL_HasDust(object oPC)
{
    return GetIsObjectValid(GetItemPossessedBy(oPC, QPAL_DUST_TAG));
}

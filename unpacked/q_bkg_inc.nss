// q_bkg_inc.nss -- Blackguard initiation "The Fall"
// (roadmap: blackguard-quest)
//
// The twelfth and last of the twelve prestige-order quests hung on Halmir
// the Grey (the prestige hub, prsg_inc.nss). Compact one-off, journal tag
// "pc_blackguard". Its signature is the thing no other order does: a
// permanent shift of the PC's alignment toward evil -- the fall itself.
//
// Flow: Halmir's Blackguards branch (prsg_conv) offers the rite to a PC
// with 1+ Blackguard level (CLASS_TYPE_BLACKGUARD = 31, verified in
// ovr/nwscript.nss -- the design gate; the hub line itself is visible from
// total level 14, existing prsg_c_bg). The trial: in the Keep of
// Barad-Dur, the Dark Tower, the instruments of cruelty still stand. The
// unique torture-rack there (existing placed instance 94 of plc_torture1
// in baraddurkeep.git.json -- retagged BkgFallAltar, made usable, its
// OnUsed now runs q_bkg_altar; it was Static with no scripts, so there is
// nothing to chain, and no code referenced the old tag "Torture
// Equipment"). Lay a hand on the rack and swear the Black Oath -- but come
// bleeding: the oath takes blood freely given or it takes nothing
// (QBKG_ComesBleeding -- GetCurrentHitPoints < GetMaxHitPoints). Swearing
// it is the fall: the rite drives the PC's alignment hard toward evil,
// ONCE, and brands a token of cold iron into the hand. Deterministic: the
// wound is the test, no dice. Carry the brand back to Halmir; the
// induction consumes it and awards the Sigil of the Fallen plus XP.
//
// Quest state is per-character and persistent via the prestige hub's
// campaign-DB stage idiom (prestigedb, order key "blackg" -- see
// prsg_inc.nss): 0 none / 1 accepted / 2 brand in hand / 3 done. One-off:
// stage 3 never resets. The alignment shift is applied only on the stage
// 1 -> 2 transition, so it can never be farmed by re-using the rack (and
// AdjustAlignment toward evil is capped at fully evil regardless). If the
// brand is somehow lost at stage 2, keeping the rite again re-gives it
// WITHOUT re-shifting (graceful, not farmable: the item is plot + cursed
// and only the finish consumes it).
//
// No new placements and no admin waypoint: the rack already stands in the
// Keep of Barad-Dur (placed instance 94 in baraddurkeep.git.json).

#include "prsg_inc"

const string QBKG_ORDER     = "blackg";           // prestigedb stage key
const string QBKG_QUEST     = "pc_blackguard";     // journal category tag
const string QBKG_BRAND_RES = "q_bkg_brand";       // reagent blueprint
const string QBKG_BRAND_TAG = "BkgBrand";
const string QBKG_SIGIL_RES = "q_bkg_sigil";       // reward blueprint
const string QBKG_SIGIL_TAG = "BkgSigil";

const int QBKG_XP = 1000;  // induction XP (L14-tier order)

// How hard the fall drives the alignment toward evil (0..100 scale;
// mirrors the module's own adj_evil.nss convention of 50). Applied once.
const int QBKG_FALL_SHIFT = 50;

// Stages (see header).
const int QBKG_STAGE_NONE     = 0;
const int QBKG_STAGE_ACCEPTED = 1;
const int QBKG_STAGE_BRAND    = 2;
const int QBKG_STAGE_DONE     = 3;

int QBKG_GetStage(object oPC)
{
    return PRSG_GetStage(oPC, QBKG_ORDER);
}

void QBKG_SetStage(object oPC, int nStage)
{
    PRSG_SetStage(oPC, QBKG_ORDER, nStage);
}

// TRUE if oPC has already broken a bright oath for a darker one -- 1+
// Blackguard level (CLASS_TYPE_BLACKGUARD = 31, verified in
// ovr/nwscript.nss). The design gate for the rite.
int QBKG_IsBlackguard(object oPC)
{
    return PRSG_HasClass(oPC, CLASS_TYPE_BLACKGUARD);
}

// The turn-in reagent check: does oPC carry the black brand?
int QBKG_HasBrand(object oPC)
{
    return GetIsObjectValid(GetItemPossessedBy(oPC, QBKG_BRAND_TAG));
}

// The oath's condition: TRUE only while oPC is wounded (blood freely
// given). Deterministic, no dice: a champion who came to the rack bleeding
// always passes; one who came whole never does. The Dark Tower is thick
// with enemies, so an aspirant reaches the rack wounded as a matter of
// course -- the wound is the offering the oath demands.
int QBKG_ComesBleeding(object oPC)
{
    return GetCurrentHitPoints(oPC) < GetMaxHitPoints(oPC);
}

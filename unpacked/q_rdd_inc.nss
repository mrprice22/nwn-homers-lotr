// q_rdd_inc.nss -- Red Dragon Disciple initiation "The Old Wyrm's Fire"
// (roadmap: red-dragon-disciple-quest)
//
// The sixth of the twelve prestige-order quests hung on Halmir the Grey
// (the prestige hub, prsg_inc.nss). Compact one-off, journal tag
// "pc_dragondisciple".
//
// Flow: Halmir's Red Dragon Disciples branch (prsg_conv) offers the trial
// to a PC with 1+ Red Dragon Disciple level (CLASS_TYPE_DRAGON_DISCIPLE
// = 37, verified in ovr/nwscript.nss -- the design gate; the hub line
// itself is visible from total level 12). The trial: in the great hall of
// the Lonely Mountain stands the Forge of Durin, and in its coals sleeps
// fire the old wyrm breathed when he took Erebor -- the fire that ruined
// Dale. The forge yields an ember only to a bare, unwarded hand: come
// wrapped in any elemental ward (Endure Elements, Resist Elements,
// Protection from Elements, Energy Buffer, Elemental Shield --
// QRDD_BloodIsWarded) and the attempt fails with a flavor message,
// nothing granted, retry allowed once the ward has lapsed or been
// dispelled. THE BLOOD MUST FEEL THE FLAME. Come unwarded and the coals
// give up the Ember of the Old Wyrm (q_rdd_ember, plot + cursed). Carry
// it back to Halmir; the induction awards the Wyrmblood Amulet plus XP
// and consumes the ember.
//
// Quest state is per-character and persistent via the prestige hub's
// campaign-DB stage idiom (prestigedb, order key "rdd" -- see
// prsg_inc.nss): 0 none / 1 accepted / 2 ember in hand / 3 done.
// One-off: stage 3 never resets. If the ember is somehow lost at stage 2,
// drawing at the forge again re-gives it (graceful, not farmable: the
// item is plot + cursed and the finish consumes it from stage 2 only).
//
// No new placements and no admin waypoint: the Forge of Durin already
// stands in the Lonely Mountain's main hall (existing placed anvil
// instance in lonelymountainma.git.json, reused -- retagged DurinForge,
// its instance OnUsed now runs q_rdd_forge; it was already usable and had
// no previous OnUsed, so there is nothing to chain).

#include "prsg_inc"

const string QRDD_ORDER      = "rdd";              // prestigedb stage key
const string QRDD_QUEST      = "pc_dragondisciple"; // journal category tag
const string QRDD_EMBER_RES  = "q_rdd_ember";      // reagent blueprint
const string QRDD_EMBER_TAG  = "WyrmEmber";
const string QRDD_AMULET_RES = "q_rdd_amulet";     // reward blueprint
const string QRDD_AMULET_TAG = "WyrmbloodAmulet";

const int QRDD_XP = 1000;  // induction XP (L12-tier order)

// Stages (see header).
const int QRDD_STAGE_NONE     = 0;
const int QRDD_STAGE_ACCEPTED = 1;
const int QRDD_STAGE_EMBER    = 2;
const int QRDD_STAGE_DONE     = 3;

int QRDD_GetStage(object oPC)
{
    return PRSG_GetStage(oPC, QRDD_ORDER);
}

void QRDD_SetStage(object oPC, int nStage)
{
    PRSG_SetStage(oPC, QRDD_ORDER, nStage);
}

// TRUE if oPC already carries the inheritance (1+ Red Dragon Disciple
// level) -- the design gate for the trial.
int QRDD_IsDisciple(object oPC)
{
    return PRSG_HasClass(oPC, CLASS_TYPE_DRAGON_DISCIPLE);
}

// The turn-in reagent check: does oPC carry the ember?
int QRDD_HasEmber(object oPC)
{
    return GetIsObjectValid(GetItemPossessedBy(oPC, QRDD_EMBER_TAG));
}

// The blood-must-feel-the-flame condition: TRUE if oPC stands wrapped in
// any of the standard elemental-ward spells (each detected with the
// GetHasSpellEffect builtin -- deterministic, no dice). While one is
// active the forge refuses the hand; let the ward lapse or dispel it and
// use the forge again. Item-borne permanent fire resistance is beyond
// script reach and deliberately not checked -- the wards a caster throws
// up are the test.
int QRDD_BloodIsWarded(object oPC)
{
    return GetHasSpellEffect(SPELL_ENDURE_ELEMENTS, oPC)
        || GetHasSpellEffect(SPELL_RESIST_ELEMENTS, oPC)
        || GetHasSpellEffect(SPELL_PROTECTION_FROM_ELEMENTS, oPC)
        || GetHasSpellEffect(SPELL_ENERGY_BUFFER, oPC)
        || GetHasSpellEffect(SPELL_ELEMENTAL_SHIELD, oPC);
}

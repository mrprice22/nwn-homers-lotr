//::///////////////////////////////////////////////
//:: Mummy Dust -- shared identity of an NPC's summoned reaper
//:: mumdust_inc
//:://////////////////////////////////////////////
/*
    The constants x2_s2_mumdust.nss (the summon) and npc_mreaper_hb.nss (the
    reaper's own heartbeat) both need. They live here so the two can never
    drift: a tag typed twice is a summon nothing counts, and a marker typed
    twice is a reaper that outlives its summoner.

    roadmap: gandalfs-mummys, wtop-court-combat-defects.
*/
//:://////////////////////////////////////////////

// Blueprints. Both carry the standard x2_def_* AI: an NPC's summon has no
// master, and the henchman AI on mummyreaper.utc would leave it standing idle.
const string MDUST_WTOP_RESREF = "wtop_mreaper";   // hostile, court-named
const string MDUST_NPC_RESREF  = "npc_mreaper";    // every other NPC caster

// Runtime tags. NOT "mummyreaper": a PC's henchman reaper carries that tag and
// must never be counted or cleaned up with an NPC's.
const string MDUST_WTOP_TAG    = "WtopMummyReaper";
const string MDUST_NPC_TAG     = "NpcMummyReaper";

// Set on the reaper at creation.
const string MDUST_MASTER   = "MDUST_MASTER";    // who summoned it
const string MDUST_SUMMONED = "MDUST_SUMMONED";  // "the summon path made me" --
                                                 // survives the summoner being
                                                 // destroyed, which the object
                                                 // local above does not

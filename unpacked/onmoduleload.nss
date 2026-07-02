//On module load
//Example of OnLoad Script


//***************************************************************************
// CONSTANTS



//***************************************************************************


//PCs Autosaving
#include "pc_export_inc"
#include "color"
#include "nwnx_admin"
#include "nwnx_events"
#include "x2_inc_switches"
#include "ru_db"
#include "admin_db"
#include "boost_db"


void main()
{

//****************************************************************************
//PCs Autosaving function
pc_export_onmoduleload();

// Force max HP on every level-up, server-wide.
NWNX_Administration_SetPlayOption(NWNX_ADMINISTRATION_OPTION_USE_MAX_HITPOINTS, TRUE);
//----------------------------------------------------------------------------

// Enable tag-based scripting for item events (e.g. Rod of Fast Buffing)
SetModuleSwitch(MODULE_SWITCH_ENABLE_TAGBASED_SCRIPTS, TRUE);

// Spawn Meaningwave NPCs at their designated waypoints
ExecuteScript("mw_spawn", GetModule());

// Double the duration of every temporary effect a player creates (eff_dur_x2).
NWNX_Events_SubscribeEvent(NWNX_ON_EFFECT_APPLIED_AFTER, "eff_dur_x2");

// Party loot: announce current roll settings when a player joins a party or the
// party leadership changes (pl_party_evt broadcasts to the whole party).
NWNX_Events_SubscribeEvent(NWNX_ON_PARTY_ACCEPT_INVITATION_AFTER, "pl_party_evt");
NWNX_Events_SubscribeEvent(NWNX_ON_PARTY_TRANSFER_LEADERSHIP_AFTER, "pl_party_evt");

// Color tokens for dialogue text (used in bank XP retirement warnings)
// CUSTOM6100 = red, CUSTOM6101 = yellow, CUSTOM6102 = close
SetCustomToken(6100, COLOR_RED);
SetCustomToken(6101, COLOR_YELLOW);
SetCustomToken(6102, COLOR_END);

// Recent Updates sign (Well of Eru): ensure the roadmapdb table exists before
// any read. It is populated externally by the roadmap editor's Publish button.
RU_InitDb();

// Admin whitelist (rest-menu Admin/Homeless options, cheat chest): ensure the
// admins table exists before any read. Seeded externally by bin/seed-admindb.sh.
Admin_InitDb();

// Premium 2x gold/XP boost subscriptions (merit redemptions 201-204): ensure the
// boostdb tables exist before any kill/quest reward reads them.
Boost_InitDb();

}   //end of main

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
#include "brd_db"
#include "admin_db"
#include "boost_db"
#include "quest_cd_inc"
#include "faction_db"
#include "worldstate_inc"
#include "ammorep_db"


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

// Module override spellscript: run stop_spellcheat before every spell impact
// script (counterspell anti-cheat + soul-fatigue on Heal/Mass Heal via
// fat_inc.nss, roadmap: heal-soul-fatigue). This MUST be installed here — the
// old on_module_load.nss that carried these lines was never wired to
// Mod_OnModLoad (the hook is this script, onmoduleload), so the override
// never ran. x2_inc_spellhook's X2RunUserDefinedSpellScript() only fires when
// the module local X2_S_UD_SPELLSCRIPT is set.
SetModuleSwitch(MODULE_VAR_OVERRIDE_SPELLSCRIPT, TRUE);
SetModuleOverrideSpellscript("stop_spellcheat");

// Spawn Meaningwave NPCs at their designated waypoints
ExecuteScript("mw_spawn", GetModule());

// Gwathdor Labyrinth (area025): re-roll the maze wiring for this reboot. Sets a
// "MAZE_DEST" local on every maze door/trigger; the doors/triggers teleport the
// PC there via gwathlab_door / gwathlab_trig. A restart = a fresh maze layout.
ExecuteScript("gwathlab_wire", GetModule());

// Double the duration of every temporary effect a player creates (eff_dur_x2).
NWNX_Events_SubscribeEvent(NWNX_ON_EFFECT_APPLIED_AFTER, "eff_dur_x2");

// Premium 2x gold/XP boost: multiply positive XP gains for players with an active
// boost (merit redemptions 201-204). Engine combat XP is not script-granted, so
// XP is intercepted centrally here rather than at kill sites. The event name has
// no const in nwnx_events.nss, so it is passed as a literal string.
NWNX_Events_SubscribeEvent("NWNX_ON_SET_EXPERIENCE_BEFORE", "boost_xp_evt");

// "Next Level" character-sheet fix for levels 40-60. The NWNX MaxLevel plugin
// leaves the sheet's next-level XP figure wrong past 40; nextlvl_inc.nss
// overrides strref 315 per player with the real requirement out of
// exptable.2da. Login is handled in mod_cliententer.nss; these two keep it
// current when the level moves (death XP loss can drain back below 40).
NWNX_Events_SubscribeEvent(NWNX_ON_LEVEL_UP_AFTER,   "nextlvl_evt");
NWNX_Events_SubscribeEvent(NWNX_ON_LEVEL_DOWN_AFTER, "nextlvl_evt");

// TEMPORARY DIAGNOSTIC -- "casters learn no new spells past 40" (roadmap
// legendary-caster-spells-on-level-up). Snapshots known-spell counts before a
// level up and reports the delta after, to establish whether the native level-up
// spell picker works above 40 at all. Delete these two lines and the three
// sk_probe_* scripts once the question is answered; see sk_probe_inc.nss.
NWNX_Events_SubscribeEvent(NWNX_ON_LEVEL_UP_BEFORE,  "sk_probe_pre");
NWNX_Events_SubscribeEvent(NWNX_ON_LEVEL_UP_AFTER,   "sk_probe_post");

// Legendary Feats: fire the level-60 picker the moment a character reaches 60.
// The picks cannot come from the engine's own level-up page — that page grants
// exactly one general feat to everybody, and legendary feats are deliberately
// invisible to it (ALLCLASSESCANUSE = 0). legfeat_lvl no-ops below level 60.
// See CLAUDE-legendary-feats.md.
NWNX_Events_SubscribeEvent(NWNX_ON_LEVEL_UP_AFTER, "legfeat_lvl");

// Party loot: announce current roll settings when a player joins a party or the
// party leadership changes (pl_party_evt broadcasts to the whole party).
NWNX_Events_SubscribeEvent(NWNX_ON_PARTY_ACCEPT_INVITATION_AFTER, "pl_party_evt");
NWNX_Events_SubscribeEvent(NWNX_ON_PARTY_TRANSFER_LEADERSHIP_AFTER, "pl_party_evt");

// Disarm catch: when an NPC disarms a PC, deposit the weapon into the PC's pack
// instead of dropping it on the ground (where it can despawn / be grabbed by the
// NPC). BEFORE snapshots the wielded weapon; AFTER moves it. PvP disarms are left
// vanilla. See disarm_catch.nss.
NWNX_Events_SubscribeEvent(NWNX_ON_DISARM_BEFORE, "disarm_catch");
NWNX_Events_SubscribeEvent(NWNX_ON_DISARM_AFTER,  "disarm_catch");

// Color tokens for dialogue text (used in bank XP retirement warnings)
// CUSTOM6100 = red, CUSTOM6101 = yellow, CUSTOM6102 = close
SetCustomToken(6100, COLOR_RED);
SetCustomToken(6101, COLOR_YELLOW);
SetCustomToken(6102, COLOR_END);

// Recent Updates sign (Well of Eru): ensure the roadmapdb table exists before
// any read. It is populated externally by the roadmap editor's Publish button.
RU_InitDb();

// Roll of the Fallen board (Well of Eru): reseed the boss registry and clear
// stale death rows — a restart revives every boss, so the board starts empty.
BRD_InitDb();

// Admin whitelist (rest-menu Admin/Homeless options, cheat chest): ensure the
// admins table exists before any read. Seeded externally by bin/seed-admindb.sh.
Admin_InitDb();

// Premium 2x gold/XP boost subscriptions (merit redemptions 201-204): ensure the
// boostdb tables exist before any kill/quest reward reads them.
Boost_InitDb();

// Quest cooldowns (daily/weekly repeatable quests): ensure the quest_cd table
// exists before any dialogue conditional reads it. See quest_cd_inc.nss.
QCD_InitDb();

// Faction allegiance (Good/Evil, persisted per-character): ensure the
// faction_standing table exists before any adjuster write or login re-apply.
// See faction_db.nss (roadmap: faction-scaffolding).
Faction_InitDb();

// World-state globals (server-wide contested control / timed buffs / weekly
// claims): ensure the world_state + world_state_rule tables exist before any
// read or before the heartbeat's WS_Tick() applies a decay/weekly rule.
// See worldstate_inc.nss (roadmap: lumber-ent-tugofwar).
WS_InitDb();

// Quiver of Endless Flight (ammo replicator, Legolas/Angmar drop): ensure the
// replicators table exists before the first activation reads a use count. Uses
// are keyed on the ITEM's UUID so they follow the quiver when it changes hands.
// See ammorep_db.nss (roadmap: Ammo-shortage).
AmmoRep_InitDb();

}   //end of main

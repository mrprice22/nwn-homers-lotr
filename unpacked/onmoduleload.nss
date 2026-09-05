//On module load
//Example of OnLoad Script


//***************************************************************************
// CONSTANTS



//***************************************************************************


//PCs Autosaving
#include "pc_export_inc"
#include "season_prof_inc"
#include "color"
#include "nwnx_admin"
#include "nwnx_events"
#include "nwnx_damage"
#include "x2_inc_switches"
#include "ru_db"
#include "brd_db"
#include "admin_db"
#include "boost_db"
#include "quest_cd_inc"
#include "faction_db"
#include "worldstate_inc"
#include "warmeter_inc"
#include "ammorep_db"
#include "cbd_db"
#include "ptm_db"
#include "merit_db"
#include "bst_db"
#include "tele_db"
#include "pw_inc"
#include "fat_inc"
#include "graf_inc"


void main()
{

// ---------------------------------------------------------------------------
// Dev-only NPCs. FIRST thing in main(), deliberately: everything below this is
// database init that could fail or hit the instruction limit, and none of it
// may be allowed to stand between a live season and the removal of a cheat NPC.
//
// SP_DEV_TOOLS is generated from SEASON_ROLE by bin/season-profile.py - on for
// the dev and early-access realms, off for a live or archived season.
//
// The NPC is DESTROYED here rather than removed from thewelloferu.git.json,
// deliberately: dev and production share one source tree and bin/season-
// promote.sh copies dev's over production's on every release, so an area file
// that differed between them would be reverted by the next deploy. Behaviour
// that differs between environments has to be a runtime decision.
//
// BUTCHA is "Ping Pong", the Ultimate PC Builder: set any level 1-60, hand out
// gold, destroy equipment.
//
// THERE ARE TWO OF HIM, identical in every respect the engine can see - same
// resref (butcha), same tag (BUTCHA), same conversation (_pc_builder_v1).
// Only the AREA tells them apart:
//
//   TheWellofEru    the PLAYER-facing one. Must not exist in a live season.
//   HouseofDispair  "House of Homer", the DM-only build room. No area
//                   transition anywhere in the module leads to it, so it is
//                   reachable only by DM teleport. This one STAYS - it is the
//                   admin's own tool, and removing it took a working DM
//                   facility away with no way to get it back.
//
// So the purge is scoped by area, not by tag. Destroying every BUTCHA is what
// the first version of this did, and it silently took the DM copy with it.
//
// THE PLOT FLAG IS WHY THIS FAILED ONCE BEFORE. Season 2 launched with the Well
// of Eru copy still standing: the creature is flagged Plot + Immortal, and
// DestroyObject() silently refuses a plot creature - no error, no log line.
// Clear both flags before destroying, and never assume DestroyObject succeeded
// on a blueprint you did not author.
//
// The conversation is independently gated by sp_devgate, which also permits
// DMs - so the House of Homer copy remains usable even where SP_DEV_TOOLS is
// off, and a stray player-side copy would still offer nothing.
if (!SP_DEV_TOOLS)
{
    int nNth = 0;
    object oDev = GetObjectByTag("BUTCHA", nNth);
    while (GetIsObjectValid(oDev))
    {
        if (GetTag(GetArea(oDev)) == "TheWellofEru")
        {
            SetPlotFlag(oDev, FALSE);
            SetImmortal(oDev, FALSE);
            DestroyObject(oDev);
        }
        // DestroyObject is deferred to the end of this script, so the NPC is
        // still enumerable and the index must advance past it either way.
        oDev = GetObjectByTag("BUTCHA", ++nNth);
    }
}
// ---------------------------------------------------------------------------


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
// fat_inc.nss, roadmap: heal-soul-fatigue). This MUST be installed here - the
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

// Devastating Critical rework (roadmap: devcrit-roll, devcrit-unarmed-save-or-die).
// devcrit_atk adds the bonus physical damage that replaces the save-or-die, in
// the NWNX Damage attack event. The rule is symmetric - no oOwner on the attack
// script, so it covers NPCs as well as players. It returns immediately on
// anything that is not a critical; read the warning in its header before
// editing it, and note that NWNX_DAMAGE_SKIP=n in server.env is the other half
// of the plugin being available at all. tests/check_devcrit.py gates this.
//
// The kill itself is stopped WITHOUT any handler here: the blank
// EpicWeaponDevastatingCriticalFeat column in hak_2da/baseitems.2da for weapon
// attacks, and DevCrit_ArmNoDevCrit (mod_cliententer / legfeat_lvl /
// nw_c2_default9) stripping the unarmed and creature feats for the attacks that
// never read that column. There WAS a third handler, devcrit_eff, subscribed to
// NWNX_ON_EFFECT_APPLIED_BEFORE to refuse the engine's EffectDeath: it was
// deleted, because UAT proved it never caught the kill and, being a per-effect
// global subscriber, it was charged with TOO MANY INSTRUCTIONS every time an
// unrelated script (Curse Song's colossal-sphere loop) overran its VM budget.
NWNX_Damage_SetAttackEventScript("devcrit_atk");

// Attack/damage bonus ledger (bonus_pool_inc): recalculate when a bonus ENDS.
// Registration and login are not enough - a song that ended early left its
// attack bonus behind, and a respawn's wholesale RemoveEffects took the
// permanent feat bonuses away with nothing to put them back. bpool_eff is
// guarded by a local that only buffed creatures carry, so an effect removal on
// anyone else costs one GetLocalInt. See its header before editing: rebuilding
// the ledger strips our own effect and fires this very event.
NWNX_Events_SubscribeEvent(NWNX_ON_EFFECT_REMOVED_AFTER, "bpool_eff");

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

// Caster spell picker: past CLASS level 40 the game client's own level-up spell
// page offers nothing but cantrips and then spends the picks anyway, so a
// wizard silently loses 2 spells a level. The tabs are disabled by a pass in
// CLIENT code, so no 2DA, hak or plugin option can reach it (roadmap
// legendary-caster-spells-on-level-up, tests A-D). The module hands the picks
// out itself and opens its own window instead; see csp_inc.nss.
//
// This line replaces the two sk_probe_* subscriptions that established the
// diagnosis - those scripts are deleted.
NWNX_Events_SubscribeEvent(NWNX_ON_LEVEL_UP_AFTER,   "csp_lvl");

// Legendary Feats: fire the level-60 picker the moment a character reaches 60.
// The picks cannot come from the engine's own level-up page - that page grants
// exactly one general feat to everybody, and legendary feats are deliberately
// invisible to it (ALLCLASSESCANUSE = 0). See CLAUDE-legendary-feats.md.
//
// LEVEL_DOWN matters as much as LEVEL_UP: a character that drops below 60 (death
// XP loss) or changes its class makeup has its picks revoked, and legfeat_lvl is
// where that is noticed. Energy drain is not a level loss and does not reach it.
NWNX_Events_SubscribeEvent(NWNX_ON_LEVEL_UP_AFTER,   "legfeat_lvl");
NWNX_Events_SubscribeEvent(NWNX_ON_LEVEL_DOWN_AFTER, "legfeat_lvl");

// Caster feat proxies (roadmap ll-bonus-feat-lists). The client hides every feat
// with a MINSPELLLVL from a caster past class level 40, so those feats are also
// published as inert per-class proxy rows the filter cannot see. This keeps the
// proxy and the real feat paired in both directions, which is what stops the
// engine offering a player a feat they already hold. See castfeat_inc.nss.
NWNX_Events_SubscribeEvent(NWNX_ON_LEVEL_UP_AFTER,   "castfeat_lvl");

// Some legendary feats are CONDITIONAL on what the character is holding -
// Legendary Onslaught grants its extra attack for melee and unarmed but not for
// a bow. legfeat_equip rebuilds those on every weapon swap; without it the
// effect goes stale silently, and an archer keeps a melee-only bonus attack.
NWNX_Events_SubscribeEvent(NWNX_ON_ITEM_EQUIP_AFTER,   "legfeat_equip");
NWNX_Events_SubscribeEvent(NWNX_ON_ITEM_UNEQUIP_AFTER, "legfeat_equip");

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

// Legendary Juggernaut's disarm immunity. The engine has no IMMUNITY_TYPE_ for
// disarm, so the only way to make a weapon unstrikable is to refuse the event.
// A second subscriber on the same event is fine - NWNX_Events runs them all.
NWNX_Events_SubscribeEvent(NWNX_ON_DISARM_BEFORE, "legfeat_disarm");

// Color tokens for dialogue text (used in bank XP retirement warnings)
// CUSTOM6100 = red, CUSTOM6101 = yellow, CUSTOM6102 = close
SetCustomToken(6100, COLOR_RED);
SetCustomToken(6101, COLOR_YELLOW);
SetCustomToken(6102, COLOR_END);

// Recent Updates sign (Well of Eru): ensure the roadmapdb table exists before
// any read. It is populated externally by the roadmap editor's Publish button.
RU_InitDb();

// Roll of the Fallen board (Well of Eru): reseed the boss registry and clear
// stale death rows - a restart revives every boss, so the board starts empty.
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

// Fangorn tug-of-war meter (isengard_warmachine): seed the neutral value on a
// virgin DB and register its 1-point-per-real-hour decay back toward neutral,
// so the rule exists on a fresh server. Idempotent - safe on every load. The
// decay itself is applied by WS_Tick() off the heartbeat. Meter layer only;
// the quest pair that pushes it is still design-queued.
// See warmeter_inc.nss (roadmap: lumber-ent-tugofwar).
WM_Init();

// Quiver of Endless Flight (ammo replicator, Legolas/Angmar drop): ensure the
// replicators table exists before the first activation reads a use count. Uses
// are keyed on the ITEM's UUID so they follow the quiver when it changes hands.
// See ammorep_db.nss (roadmap: Ammo-shortage).
AmmoRep_InitDb();

// Schema setup for the campaign DBs. ALL of it belongs here and nowhere else:
// module load runs once, before any player can connect, whereas the client-enter
// hook used to re-run seven of these per login - 28 synchronous SQLite commits
// against seven DB files on the login frame, on one spinning disk and a
// single-threaded server main loop. That was the login stall players reported.
// Adding a table to any of these subsystems needs no client-enter change.
//
// Per-character play time. A row left open by a crash or the nightly reboot is
// never closed retroactively; it simply keeps a NULL `minutes` and every reader
// skips it. See ptm_db.nss.
Ptm_InitDb();

// Merit economy (award + redemption ledger). Carries PRAGMA table_info-guarded
// ALTER TABLE migrations, so it must run on every load, not just a fresh DB.
Merit_InitDb();

// Bestiary kill tracking.
Bst_InitDb();

// Teleport / travel destinations.
Tele_InitDb();

// Combat Dummy leaderboard ("Hall of Champions" sign): ensure the sessions
// table exists before the first trial finishes or the first sign read. The
// dummy's own OnSpawn calls this too, so a dummy placed in a module whose load
// order never reached here still records. See cbd_db.nss (roadmap: combat-dummy).
Cbd_InitDb();

// Concerning Pipeweed: the pipe-weed high is stored per character (strain +
// real-world expiry) rather than applied as a plain temporary effect, so that
// resting cannot scrub the penalty half of the trade. Ensure the table exists
// before the first pipe is lit or the first login reapply reads it.
// See pw_inc.nss (roadmap: concerning-pipeweed).
PW_InitDb();

// Soul-fatigue on the full-heal spells: stacks now persist per character and
// their decay pauses while the player is offline, so the queue lives in a
// campaign DB rather than a local int. Ensure the table exists before the
// first heal lands or the first login tries to restore a queue.
// See fat_inc.nss (roadmap: heal-soul-fatigue-rebalance).
FAT_InitDb();
// ... and then clear it. Soul-fatigue does not survive a reboot: no combat did.
// Every boss and creature that ran a player's stacks up has just been reset by
// this very load, so the healing debt resets with them. Stacks persist across a
// LOGOUT (that is the anti-dodge rule), never across a restart.
FAT_WipeAll();

// Well of Eru graffiti easel (merit reward 301): the player's chosen appearance
// lives in graffitidb, but the canvas showing it is a script-created placeable,
// which no reboot preserves. Recreate the schema, then repaint whatever the
// easel was last displaying - a pick is meant to survive everything short of a
// DM setting it in stone. See CLAUDE-graffiti.md.
Graf_InitDb();
Graf_RestoreCanvas();

}   //end of main

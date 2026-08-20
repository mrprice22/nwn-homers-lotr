//::///////////////////////////////////////////////
//:: sp_devgate_inc - who may use the dev-tool NPCs
//::
//:: ONE predicate, used by both halves of the gate:
//::   sp_devgate.nss      the StartingConditional that shows the conversation
//::   _build_lvl_inc.nss  the script that actually sets a legendary level
//::
//:: They must agree. When they did not, the result was the worst kind of bug:
//:: on season 2 an admin could open Ping Pong in House of Homer, pick a level
//:: between 41 and 60, and NOTHING HAPPENED - no effect, no message, no reason
//:: given. The conversation gate allowed the admin through, and then the level
//:: script bailed on a bare SP_DEV_TOOLS test that knew nothing about admins.
//:: Levels 1-40 worked the whole time, which made it look even more arbitrary.
//::
//:: THE RULE. Dev tools are open to everyone on a realm that has them enabled
//:: (dev / early access), and to a whitelisted admin ANYWHERE - including a
//:: live season. That is deliberate: House of Homer is reachable only by the
//:: rest menu's admin teleport, which is gated on the SAME admindb whitelist,
//:: so anyone standing in front of the NPC has already passed this test once.
//::
//:: Admin_CanAdmin reads admins.can_admin from the admindb campaign database
//:: (seeded out of band by bin/seed-admindb.sh); no CD key ever ships in the
//:: .mod. Do NOT substitute GetIsDM() - it is TRUE only for an actual DM-client
//:: login, and this server's admin has no DM console, so it would make the NPC
//:: mute for the one person who is supposed to use it.
//:://////////////////////////////////////////////
#include "season_prof_inc"
#include "admin_db"

// TRUE if oPC may use the dev-tool NPCs on this realm.
int SP_DevToolsFor(object oPC);

int SP_DevToolsFor(object oPC)
{
    if (SP_DEV_TOOLS) return TRUE;
    return Admin_CanAdmin(oPC);
}

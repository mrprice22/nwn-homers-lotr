// dbg_combat.nss - admin toggle for the combat diagnostics.
//
// Turns BOTH temporary diagnostic modes on or off together, module-wide:
//
//   DEVCRIT_DEBUG (devcrit_inc)  every effect landing on a victim inside a
//                                devastating critical's no-kill window is
//                                reported with its raw internal TYPE - the
//                                measurement that says whether the engine's
//                                dev-crit kill is an applied effect at all.
//   CBD_DEBUG     (cbd_inc)      the Combat Dummy echoes every attack and every
//                                damage packet with its raw event fields, so
//                                "the numbers look low" can be reconciled
//                                against the combat log packet by packet.
//
// HOW IT IS ACTUALLY TRIGGERED: it is not, by hand. The admin does not use a DM
// client, so `dm_runscript dbg_combat` is not a route that exists here (see
// CLAUDE.md, "The admin has no DM console"). The Combat Dummy diagnostic arms
// ITSELF for an admin owner at session start (CBD_StartSession), which is what
// the UAT actually uses. This script stays as the server-wide switch for the
// devcrit half, callable from a rest-menu Admin Options entry or
// ExecuteScript("dbg_combat", GetModule()) - wire it to the menu before relying
// on it.
//
// Gated on the admindb whitelist, same as every other admin-only feature - a
// non-admin running it changes nothing. Both flags are OFF at every reboot:
// they live on the module object and nothing persists them, deliberately.
//
// This is a diagnostic, not a game system. Delete this file and the two debug
// blocks it drives once the devastating-critical and Combat Dummy questions in
// roadmap devcrit-roll / combat-dummy are answered.

#include "admin_db"
#include "devcrit_inc"
#include "cbd_inc"

void main()
{
    object oPC = OBJECT_SELF;
    object oMod = GetModule();

    // DMs are trusted here as well as the CD-key whitelist: dm_runscript is a
    // DM-only console command in the first place.
    if (GetIsPC(oPC) || GetIsDM(oPC))
    {
        if (!GetIsDM(oPC) && !Admin_CanAdmin(oPC))
        {
            SendMessageToPC(oPC, "You are not authorised to use that.");
            return;
        }
    }
    else
    {
        oPC = OBJECT_INVALID;   // called from the module: report to DMs only
    }

    int nOn = !GetLocalInt(oMod, DEVCRIT_VAR_DEBUG);

    SetLocalInt(oMod, DEVCRIT_VAR_DEBUG, nOn);
    SetLocalInt(oMod, CBD_VAR_DEBUG,     nOn);

    string sMsg = "[DEBUG] combat diagnostics (devcrit + combat dummy) are now " +
                  (nOn ? "ON" : "OFF") + ".";

    if (GetIsObjectValid(oPC)) SendMessageToPC(oPC, sMsg);
    else SendMessageToAllDMs(sMsg);
}

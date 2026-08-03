// dbg_combat.nss - admin toggle for the combat diagnostics.
//
// Turns BOTH temporary diagnostic modes on or off together, module-wide:
//
//   DEVCRIT_DEBUG (devcrit_inc)  every effect landing on a victim inside a
//                                devastating critical's no-kill window is
//                                reported with its raw internal TYPE.
//   CBD_DEBUG     (cbd_inc)      the Combat Dummy echoes every attack and every
//                                damage packet with its raw event fields and
//                                the branch it took, so the reported figures
//                                can be reconciled against the combat log.
//
// TRIGGER: the rest menu, Admin Options -> "[Admin] Combat diagnostics on/off"
// (emotewand.dlg reply 139, action-taken script). NOT a DM console command -
// the admin does not use a DM client, so `dm_runscript` is not a route that
// exists here; see CLAUDE.md, "The admin has no DM console".
//
// The Combat Dummy also arms itself for an admin owner at session start
// (CBD_StartSession), so an admin's own test set is instrumented whether this
// toggle is on or not. This switch is what turns the dump on for a NON-admin
// tester's session, and what turns the devcrit half on at all.
//
// Gated on the admindb whitelist. Both flags live on the module object and
// nothing persists them, so they are OFF at every reboot, deliberately.
//
// This is a diagnostic, not a game system. Delete this file, the dialog reply,
// and the two debug blocks it drives once the devastating-critical and Combat
// Dummy questions in roadmap devcrit-roll / combat-dummy are answered.

#include "admin_db"
#include "devcrit_inc"
#include "cbd_inc"

void main()
{
    // Action-taken script on a dialog reply: the speaker is the admin. Falls
    // back to OBJECT_SELF so ExecuteScript("dbg_combat", oPC) also works.
    object oPC = GetPCSpeaker();
    if (!GetIsObjectValid(oPC)) oPC = OBJECT_SELF;

    object oMod = GetModule();

    if (GetIsPC(oPC) && !GetIsDM(oPC) && !Admin_CanAdmin(oPC))
    {
        SendMessageToPC(oPC, "You are not authorised to use that.");
        return;
    }

    int nOn = !GetLocalInt(oMod, DEVCRIT_VAR_DEBUG);

    SetLocalInt(oMod, DEVCRIT_VAR_DEBUG, nOn);
    SetLocalInt(oMod, CBD_VAR_DEBUG,     nOn);

    string sMsg = CBD_DEBUG_COLOR + "[DEBUG] combat diagnostics (devcrit + " +
                  "combat dummy) are now " + (nOn ? "ON" : "OFF") + "." +
                  COLOR_END;

    if (GetIsPC(oPC)) SendMessageToPC(oPC, sMsg);
    else SendMessageToAllDMs(sMsg);
}

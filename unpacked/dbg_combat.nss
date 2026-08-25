// dbg_combat.nss - admin toggle for the combat diagnostics.
//
// Turns ALL the temporary diagnostic modes on or off together, module-wide:
//
//   DEVCRIT_DEBUG (devcrit_inc)  every effect landing on a victim inside a
//                                devastating critical's no-kill window is
//                                reported with its raw internal TYPE.
//   CBD_DEBUG     (cbd_inc)      the Combat Dummy echoes every attack and every
//                                damage packet with its raw event fields and
//                                the branch it took, so the reported figures
//                                can be reconciled against the combat log.
//   SHAPE_MERGE_DEBUG            every rung of the polymorph item-merge ladder
//   (shape_merge_inc)            reports the equipment slots it saw, whether
//                                it judged the form ready, and whether it
//                                merged - for tensors-transformation-not-
//                                merging-items-reliably.
//
// TRIGGER: the rest menu, Admin Options -> "[Admin] Combat diagnostics on/off"
// (emotewand.dlg reply 139, action-taken script). NOT a DM console command -
// the admin does not use a DM client, so `dm_runscript` is not a route that
// exists here; see CLAUDE.md, "The admin has no DM console".
//
// This is the ONLY switch. An earlier build also armed the dummy's dump
// automatically for an admin owner, which made this menu entry lie: turning it
// OFF left the admin still seeing the diagnostic. That auto-arm is gone.
//
// Gated on the admindb whitelist. Both flags live on the module object and
// nothing persists them, so they are OFF at every reboot, deliberately.
//
// This is a diagnostic, not a game system. Delete this file, the dialog reply,
// and the debug blocks it drives once the devastating-critical, Combat Dummy
// and polymorph-merge questions in roadmap devcrit-roll / combat-dummy /
// tensors-transformation-not-merging-items-reliably are answered.

#include "admin_db"
#include "devcrit_inc"
#include "cbd_inc"
#include "shape_merge_inc"

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
    SetLocalInt(oMod, SHAPE_VAR_DEBUG,   nOn);

    // Red while it is on (it is instrumentation, and it should look like it),
    // green to confirm the log is clean again.
    string sColor = nOn ? CBD_DEBUG_COLOR : CBD_COLOR_FINAL;
    string sMsg = sColor + "[DEBUG] combat diagnostics (devcrit + combat dummy "
                  + "+ shape merge) "
                  + "are now " + (nOn ? "ON" : "OFF") + "." + COLOR_END;

    if (GetIsPC(oPC)) SendMessageToPC(oPC, sMsg);
    else SendMessageToAllDMs(sMsg);
}

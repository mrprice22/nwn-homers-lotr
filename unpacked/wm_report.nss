// wm_report.nss - admin readout for the Isengard war-machine meter.
//
// Roadmap: lumber-ent-tugofwar. Prints the current state of the Fangorn
// tug-of-war meter (warmeter_inc.nss over worldstate_inc / worldstatedb):
// the player-facing normalized sentence, the band, and - because this surface
// is admin-only - the raw 0..200 back-end value for tuning and UAT.
//
// TRIGGER: rest menu / emote wand, Admin Options -> "[Admin] Fangorn war meter"
// (emotewand.dlg, action-taken script on the reply gated by the _cdkey admindb
// check on the parent Admin Options node). NOT a DM console command - the admin
// does not use a DM client; see CLAUDE.md, "The admin has no DM console".
//
// Read-only by design. It never pushes the meter: what pushes it is the quest
// pair's qualifying actions, which are still an open design question.

#include "admin_db"
#include "warmeter_inc"

void main()
{
    // Action-taken script on a dialog reply: the speaker is the admin. Falls
    // back to OBJECT_SELF so ExecuteScript("wm_report", oPC) also works.
    object oPC = GetPCSpeaker();
    if (!GetIsObjectValid(oPC)) oPC = OBJECT_SELF;

    if (GetIsPC(oPC) && !GetIsDM(oPC) && !Admin_CanAdmin(oPC))
    {
        SendMessageToPC(oPC, "You are not authorised to use that.");
        return;
    }

    int nRaw  = WM_Get();
    int nBand = WM_GetBandOf(nRaw);

    string sMsg = "[Fangorn war meter] " + WM_GetStatusText() +
                  " Band: " + WM_GetBandName(nBand) +
                  " (" + IntToString(nBand) + "/4)." +
                  " Raw (admin only): " + IntToString(nRaw) +
                  " of " + IntToString(WM_MIN) + ".." + IntToString(WM_MAX) +
                  ", neutral " + IntToString(WM_NEUTRAL) +
                  ", decay " + IntToString(WM_DECAY_RATE) + " per " +
                  IntToString(WM_DECAY_PERIOD) + "s toward neutral.";

    if (GetIsPC(oPC)) SendMessageToPC(oPC, sMsg);
    else SendMessageToAllDMs(sMsg);
}

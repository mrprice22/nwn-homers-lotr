// cp_announce -- Crash Party: fire the next scheduled announcement.
//
// Control-room placeable, OnUsed. Steps through a fixed countdown script one
// press at a time, so the DM controls the pacing without having to type anything
// or remember what was said last.
//
// Sequence resets whenever the master switch is thrown, so a second party starts
// from the top. Past the end it falls through to a generic "still going" shout
// that can be pressed as often as you like.
//
// All of it goes through CP_Broadcast (cp_inc.nss) -- the module has no
// SendMessageToAllPCs wrapper of its own.
//
// Text is deliberately season-neutral: bin/season-brand.py owns the season
// strings and tests/check_season_brand.py fails the repack on a hardcoded one.

#include "cp_dm_inc"

const string CP_ANN_STEP = "CP_ANN_STEP";

void main()
{
    object oPC = GetLastUsedBy();
    if (!CP_DmGate(oPC)) return;

    int nStep = GetLocalInt(GetModule(), CP_ANN_STEP);
    string sMsg;

    switch (nStep)
    {
        case 0:
            sMsg = "The Crash Party starts in ONE HOUR. Come to the Well of Eru -- " +
                   "we are trying to break the server's all-time record for players online.";
            break;
        case 1:
            sMsg = "THIRTY MINUTES to the Crash Party. Drag a friend along; every " +
                   "single body counts toward the record.";
            break;
        case 2:
            sMsg = "TEN MINUTES. Head to the Well of Eru now.";
            break;
        case 3:
            sMsg = "The Crash Party begins NOW! Free party favours at the Well of Eru, " +
                   "and they are yours to keep afterwards.";
            break;
        case 4:
            sMsg = "Still going at the Well of Eru -- log in, grab your favours, " +
                   "help us hold the record.";
            break;
        default:
            sMsg = "The Crash Party is still going at the Well of Eru. Everyone welcome.";
            break;
    }

    CP_Broadcast("*** " + sMsg + " ***", COLOR_YELLOW);
    SetLocalInt(GetModule(), CP_ANN_STEP, nStep + 1);

    SendMessageToPC(oPC, "Announcement " + IntToString(nStep)
        + " sent to " + IntToString(CP_OnlineCount()) + " player(s).");
}

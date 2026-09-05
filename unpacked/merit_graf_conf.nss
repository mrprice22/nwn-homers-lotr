// merit_graf_conf.nss - the player confirms their mark. Writes it onto the open
// redemption row as the admin-facing note (seen in the EmoteWand pending list
// and on the roadmap editor's Pending Requests panel) and frees the easel.
//
// Re-confirmable on purpose: the request stays pending until a DM fulfils it,
// so a change of heart just overwrites the note.
#include "merit_redeem"
#include "graf_inc"
void main()
{
    object oPC = GetPCSpeaker();
    Graf_InitDb();

    int nReqId = Merit_PendingIdFor(GetPCPublicCDKey(oPC), MERIT_REWARD_GRAFFITI);
    if (nReqId <= 0) return;

    struct graf_pick p = Graf_GetPick(oPC);
    if (p.appearance <= 0) return;

    string sNote = "appearance " + IntToString(p.appearance)
        + " - " + p.app_name + " [" + p.category + "]";
    if (p.name != "")  sNote += " | name: " + p.name;
    if (p.descr != "") sNote += " | desc: " + p.descr;

    Merit_SetRedemptionNote(nReqId, sNote);
    Graf_Release(oPC);

    SendMessageToPC(oPC, "[Merit] Noted on request #" + IntToString(nReqId)
        + ": " + sNote);
    SendMessageToAllDMs("[Merit] " + GetPCPlayerName(oPC) + " confirmed graffiti #"
        + IntToString(nReqId) + ": " + sNote);
}

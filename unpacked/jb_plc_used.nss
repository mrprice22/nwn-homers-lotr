// jb_plc_used.nss - OnUsed for the player jukebox placeable (jb_jukebox_plc).
//
// Opens the song browser (jb_nui). The blueprint still carries jb_conv in its
// Conversation field as a fallback, but nothing reads it while this window
// works - a NUI list of 113 tracks with a search box is the whole reason the
// placeable exists, and the conversation can only show 8 of the 5 custom ones.
#include "jb_nui"

void main()
{
    object oPC = GetLastUsedBy();
    if (!GetIsPC(oPC)) return;

    // Defensive, and cheap: an existing database does one COUNT and returns.
    // graf_use.nss does the same rather than trusting module load alone.
    JB_InitDb();

    // Settle before drawing. This is the lazy half of the queue's timekeeping:
    // it retires a finished song, promotes the next, and re-asserts one that was
    // still running when the server restarted - so the window never shows a room
    // state that the engine has quietly forgotten.
    JB_Reconcile(GetArea(oPC));

    JB_NuiOpen(oPC);
}

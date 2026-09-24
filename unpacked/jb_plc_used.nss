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

    JB_NuiOpen(oPC);
}

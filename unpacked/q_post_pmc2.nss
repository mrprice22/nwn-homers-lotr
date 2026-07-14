// Hobbit Post (roadmap: hobbit-post)
// StartingConditional: TRUE while the PC is still carrying an undelivered
// parcel. Sets tokens 6340/6341 to the addressee on its label so Posco can
// remind the player where it goes (and offer to re-address it).
#include "q_post_inc"

int StartingConditional()
{
    object oPC = GetPCSpeaker();
    int nLabel = QP_Label(oPC);
    if (nLabel == 0)
        return FALSE;
    SetCustomToken(6340, QP_Name(nLabel));
    SetCustomToken(6341, QP_Place(nLabel));
    return TRUE;
}

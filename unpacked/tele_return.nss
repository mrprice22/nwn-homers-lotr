// tele_return — Rest-menu return to your last Well-of-Eru save point (unlock
// 102). One-shot: it disarms after use, so it cannot be used twice in a row
// without teleporting to the Well of Eru again (death never re-arms it).
#include "tele_db"
void main()
{
    object oPC = GetPCSpeaker();
    if (!Tele_GetArmed(oPC) || !Tele_HasSlot(oPC, 0))
    {
        SendMessageToPC(oPC, "[Teleport] You have no armed Well-of-Eru return point. "
            + "Use the 'To. The Well of Eru.' teleport first.");
        return;
    }
    Tele_DoJump(oPC, Tele_SlotLocation(oPC, 0), VFX_FNF_SUMMON_GATE, VFX_IMP_RAISE_DEAD);
    Tele_SetArmed(oPC, FALSE);
}

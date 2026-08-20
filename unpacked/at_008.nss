//::///////////////////////////////////////////////
//:: FileName at_008
//:://////////////////////////////////////////////
//:: Gondor Scribe -- Azagoth's head turn-in. The quest's one reward node.
//::
//:: Pays 10,000 XP, consumes the head, advances the stage (questcddb stamp +
//:: journal "The Well of Souls" entry 2) and grants the Annuminas Key.
//::
//:: The WOS_Done guard is what stops a second head from re-paying the XP: the
//:: head is consumed here, but Azagoth respawns, so without it a player could
//:: farm the reward by bringing another one. sc_003 gates the node on the same
//:: flag; this is the second lock in case the node is reached another way.
//::
//:: The key is granted here, once per character ever (WOS_GiveKey). One key
//:: opens exactly one of the two warded Annuminas coffers -- it self-destroys
//:: on use -- so the sorcerer/wizard choice is permanent. The scribe's own
//:: dialogue explains that in character.
//:://////////////////////////////////////////////
#include "nw_i0_tool"
#include "wos_inc"

void main()
{
    object oPC = GetPCSpeaker();

    // Already rewarded on this character? Take nothing, give nothing.
    if (WOS_Done(oPC)) return;

    RewardPartyXP(10000, oPC);

    object oItemToTake = GetItemPossessedBy(oPC, "azagothshead");
    if (GetIsObjectValid(oItemToTake))
        DestroyObject(oItemToTake);

    WOS_Complete(oPC);
    WOS_GiveKey(oPC);
}

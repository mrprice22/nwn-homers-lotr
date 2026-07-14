//::///////////////////////////////////////////////
//:: FileName at_hanee_head
//:://////////////////////////////////////////////
/*
    Hanee the Loon (Bree) - intermediate reward for
    bringing back Azagoth's Head: 5,000 XP, one time.
    She does NOT take the head - the player carries it
    on to the Gondor Scribe (Tower of the High Wizard)
    for the 10,000 XP turn-in. Advances the
    "Ruin of Annuminas" journal to entry 2.
    (roadmap: gondor-scribe)
*/
//:://////////////////////////////////////////////
#include "nw_i0_tool"

void main()
{
    object oPC = GetPCSpeaker();

    // Intermediate reward - one time only (flag checked by sc_hanee_head)
    RewardPartyXP(5000, oPC);
    SetLocalInt(oPC, "hanee_head_reward", 1);

    // Hand off to the Gondor wizards - keep the head on the player
    AddJournalQuestEntry("Ruin of Annuminas", 2, oPC);
}

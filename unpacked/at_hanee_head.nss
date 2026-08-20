//::///////////////////////////////////////////////
//:: FileName at_hanee_head
//:://////////////////////////////////////////////
/*
    Hanee the Loon (Bree) - intermediate reward for
    bringing back Azagoth's Head: 5,000 XP, one time.
    She does NOT take the head - the player carries it
    on to a Gondor Scribe (Tower of the High Wizard, or
    the one keeping camp in the Ruins of Annuminas) for
    the 10,000 XP turn-in. Advances the "Ruin of
    Annuminas" journal to entry 2.
    (roadmap: gondor-scribe)

    The one-time gate used to be a session local int
    ("hanee_head_reward"), which meant a relog cleared it
    and the 5,000 XP could be collected again on the same
    head - Hanee never takes it. It is now a questcddb
    stamp, so it survives logout and reboots. Same fix,
    and same reason, as the scribe's own quest state.
*/
//:://////////////////////////////////////////////
#include "nw_i0_tool"
#include "quest_cd_inc"

void main()
{
    object oPC = GetPCSpeaker();

    // Intermediate reward - once per character, ever (gate: sc_hanee_head)
    if (QCD_LastStamp(oPC, "hanee_head") != 0) return;

    RewardPartyXP(5000, oPC);
    QCD_Stamp(oPC, "hanee_head");

    // Hand off to the Gondor wizards - keep the head on the player
    AddJournalQuestEntry("Ruin of Annuminas", 2, oPC);
}

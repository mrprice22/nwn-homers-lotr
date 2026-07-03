//::///////////////////////////////////////////////
//:: Dragon Knight
//:: X2_S2_DragKnght
//:: Copyright (c) 2001 Bioware Corp.
//:://////////////////////////////////////////////
/*
     Summons an adult red dragon for you to
     command.
*/
//:://////////////////////////////////////////////
//:: Created By: Andrew Nobbs
//:: Created On: Feb 07, 2003
//:://////////////////////////////////////////////
#include "x2_inc_toollib"

#include "x2_inc_spellhook"
#include "epic_summon_inc"
void main()
{

    /*
      Spellcast Hook Code
      Added 2003-06-20 by Georg
      If you want to make changes to all spells,
      check x2_inc_spellhook.nss to find out more
    */
    if (!X2PreSpellCastCode())
    {
    // If code within the PreSpellCastHook (i.e. UMD) reports FALSE, do not run this spell
        return;
    }

    // Epic summon: spawn the dragon knight as a timed henchman so it can be out
    // alongside a normal summon-animal. See epic_summon_inc.nss.
    // Duration fixed to 30 hours (the old code used RoundsToSeconds -> ~3 min).
    EpicSummon_Cast(OBJECT_SELF, "epicdragonknight", GetSpellTargetLocation(),
                    HoursToSeconds(30), 460);
}



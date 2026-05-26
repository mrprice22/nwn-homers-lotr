//* Dragon 'takes' hill giant head
#include "M3PlotInclude"
#include "nw_i0_plot"

void main()
{
    object oPC = GetPCSpeaker();

    // Anti-exploit: player can drop the head mid-conversation to keep it.
    if (!PlayerHasHillGiantChiefHead(oPC))
    {
        FloatingTextStringOnCreature(
            "You must have the Hill Giant Chief's head in your possession.", oPC, FALSE);
        return;
    }

    TakeHillGiantChiefHead(oPC);
    RewardXP("M3Q04_C03_AKUL", 100, oPC);
    SetLocalInt(OBJECT_SELF, "AkulaPlotDone", 1);
    SetLocalInt(OBJECT_SELF, "NW_G_M3Q4EA_HILLGIANTHEAD", 1);
}

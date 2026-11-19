//::///////////////////////////////////////////////
//:: FileName sc_021
//:: King Theoden: the PC carries the White Hand Destroyer's scythe.
//:: Tag WhiteHandScythe (whitehandscythe.uti), not the stock NW_WPLMSC004
//:: that Tagget's store sells (roadmap: mystic-theoden-quest-state).
//:://////////////////////////////////////////////
#include "nw_i0_tool"

int StartingConditional()
{
    return CheckPlayerForItem(GetPCSpeaker(), "WhiteHandScythe");
}

// legfeat_lvl.nss — NWNX_ON_LEVEL_UP_AFTER handler for Legendary Feats.
// Subscribed in onmoduleload.nss.
//
// Fires the picker the moment a character reaches level 60. Below 60 it does
// nothing, and it costs one GetHitDice per level-up.
//
// The allotment is granted here (via legfeat_open) rather than at login so that
// the picks and the window arrive together, at the moment the player earned
// them. A dismissed window is recoverable from the rest menu; the DB row is
// already written by then, so nothing is lost.
//
// Delayed by a beat: at NWNX_ON_LEVEL_UP_AFTER the engine is still finishing the
// level-up (the client's own level-up UI is on screen), and opening a NUI window
// into that is how you get a window the player cannot interact with.

#include "legfeat_inc"

void main()
{
    object oPC = OBJECT_SELF;
    if (!GetIsPC(oPC) || GetIsDM(oPC)) return;
    if (GetHitDice(oPC) < LEGFEAT_LEVEL) return;

    DelayCommand(2.0, ExecuteScript("legfeat_open", oPC));
}

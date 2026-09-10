// cp_tipsy -- Crash Party: the Magical Tankard's after-effects ticker.
//
// Self-scheduling per-PC chain, in the shape _spfail_cycle.nss established: a
// guard on the PC plus a tail DelayCommand back into this same script.
// Deliberately NOT on the module heartbeat (bleeding.nss) -- that pulse is
// already heavily loaded, and frame time is the exact number the crash party
// exists to measure.
//
// ## There is exactly one chain per drinker
//
// This script tail-schedules itself, so it must never be started twice for the
// same PC: a second chain would double the belch rate, a third would triple it,
// and the sixth drink would produce a fit every couple of seconds forever. The
// guard is CP_TIPSY_NEXT -- the wall-clock time the next tick is due -- which
// cp_tankard.nss checks before starting anything and which this script refreshes
// on every tick. A timestamp rather than a boolean, because creature locals are
// serialised into the .bic and a flag stranded TRUE by a restart would lock the
// chain off for good; a stale timestamp just falls into the past.
//
// Everything here is cosmetic: an animation and a sound. No knockdown effect,
// nothing that touches combat, nothing another player can be hit with.

#include "cp_inc"

const string CP_TIPSY_VAR  = "CP_TIPSY";
const string CP_TIPSY_END  = "CP_TIPSY_UNTIL";
const string CP_TIPSY_NEXT = "CP_TIPSY_NEXT";

void main()
{
    object oPC = OBJECT_SELF;
    if (!GetIsPC(oPC)) return;

    int nTipsy = GetLocalInt(oPC, CP_TIPSY_VAR);
    int nUntil = GetLocalInt(oPC, CP_TIPSY_END);

    // Sobered up (or never started): tidy up and let the chain die.
    if (nTipsy <= 0 || CP_Now() >= nUntil)
    {
        if (nTipsy > 0) SendMessageToPC(oPC, "Your head clears. Mostly.");
        DeleteLocalInt(oPC, CP_TIPSY_VAR);
        DeleteLocalInt(oPC, CP_TIPSY_END);
        DeleteLocalInt(oPC, CP_TIPSY_NEXT);
        return;
    }

    AssignCommand(oPC, PlaySound(CP_BelchSound(nTipsy)));

    // Below the cap it is a stagger; past it, a full pratfall. Either way the PC
    // gets control straight back -- ActionPlayAnimation is interruptible and
    // locks nobody out of a fight.
    if (nTipsy >= 4 && Random(3) == 0)
    {
        AssignCommand(oPC,
            ActionPlayAnimation(ANIMATION_LOOPING_DEAD_FRONT, 1.0, IntToFloat(Random(3) + 2)));
        AssignCommand(oPC, ActionPlayAnimation(ANIMATION_FIREFORGET_PAUSE_BORED, 1.0));
        ApplyEffectToObject(DURATION_TYPE_INSTANT,
            EffectVisualEffect(VFX_IMP_CONFUSION_S), oPC);
    }
    else
    {
        AssignCommand(oPC,
            ActionPlayAnimation(ANIMATION_LOOPING_PAUSE_DRUNK, 1.0, IntToFloat(Random(4) + 2)));
    }

    // Tipsier means the fits come closer together: 20-40s sober-ish, down to
    // roughly 8-18s at the cap.
    int nGap = 20 - nTipsy;
    if (nGap < 8) nGap = 8;
    nGap += Random(11);

    // Refresh the ownership stamp BEFORE scheduling, with slack, so cp_tankard
    // can see that a live chain still owns this PC.
    SetLocalInt(oPC, CP_TIPSY_NEXT, CP_Now() + nGap + 5);
    DelayCommand(IntToFloat(nGap), ExecuteScript("cp_tipsy", oPC));
}

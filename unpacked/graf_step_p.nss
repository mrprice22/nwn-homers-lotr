// graf_step_p.nss - nudge one appearance back inside the current category.
#include "graf_inc"
void main()
{
    object oPC = GetPCSpeaker();
    Graf_ClaimOk(oPC);
    Graf_Step(oPC, -1);
    Graf_Summary(oPC);
}

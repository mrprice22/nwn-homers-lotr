// graf_step_n.nss - nudge one appearance forward inside the current category.
#include "graf_inc"
void main()
{
    object oPC = GetPCSpeaker();
    Graf_ClaimOk(oPC);
    Graf_Step(oPC, 1);
    Graf_Summary(oPC);
}

//:: mw_ctr_pulse -- 1-second counterspell detection pulse for caster guides.
//:: Scheduled by MW_CtrEnsurePulse; runs MW_CounterspellPulse, which detects an
//:: enemy mid-cast, rolls the opposed Spellcraft check, interrupts on success,
//:: and reschedules itself until the guide leaves counterspell mode.
#include "mw_counter_inc"
void main()
{
    MW_CounterspellPulse();
}

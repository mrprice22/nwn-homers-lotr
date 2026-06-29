//:: mw_def_damaged -- OnDamaged for MeaningWave caster guides.
//:: In counterspell mode (MW_STYLE 3) the guide stands ground and lets the
//:: detection pulse do the work instead of running the stock AI (which would
//:: resume casting). Otherwise defer to the default handler.
#include "mw_counter_inc"
void main()
{
    if (MW_Style3()) { MW_CtrEnsurePulse(); return; }
    ExecuteScript("x2_def_ondamage", OBJECT_SELF);
}

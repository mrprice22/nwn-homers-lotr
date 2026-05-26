location lTarget;
object oTarget;
void main()
{

object oPC = GetLastUsedBy();

if (!GetIsPC(oPC)) return;

int nAlign = GetAlignmentGoodEvil(oPC);
int nVFX;
if (nAlign == ALIGNMENT_GOOD)
    nVFX = VFX_IMP_GOOD_HELP;
else if (nAlign == ALIGNMENT_EVIL)
    nVFX = VFX_IMP_EVIL_HELP;
else
    nVFX = VFX_IMP_LIGHTNING_S;

ApplyEffectToObject(DURATION_TYPE_INSTANT, EffectVisualEffect(nVFX), oPC);

oTarget = GetWaypointByTag("WP_numenor");
lTarget = GetLocation(oTarget);
if (GetAreaFromLocation(lTarget) == OBJECT_INVALID) return;

AssignCommand(oPC, ClearAllActions());
DelayCommand(1.0, AssignCommand(oPC, ActionJumpToLocation(lTarget)));

}

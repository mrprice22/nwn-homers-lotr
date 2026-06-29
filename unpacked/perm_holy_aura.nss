//OnHeartbeat of a Placeable Object (Which must NOT be Static!)
void main()
{

int DoOnce = GetLocalInt(OBJECT_SELF, GetTag(OBJECT_SELF));

if (DoOnce==TRUE) return;

SetLocalInt(OBJECT_SELF, GetTag(OBJECT_SELF), TRUE);

object oTarget;
oTarget = OBJECT_SELF;


ApplyEffectToObject(DURATION_TYPE_PERMANENT, EffectVisualEffect(VFX_DUR_PROTECTION_GOOD_MAJOR), oTarget);

}

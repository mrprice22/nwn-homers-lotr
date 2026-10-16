// hw_pking_rnd - Pumpkin King end-of-round: every third round he raises a
// cursed pumpkin beside himself (which feeds the attack aura around him), then
// the stock combat round runs.

#include "hw_inc"

void main()
{
    object oKing = OBJECT_SELF;
    int n = GetLocalInt(oKing, "hw_round") + 1;
    SetLocalInt(oKing, "hw_round", n);
    if (n % 3 == 0 && HW_Phase() == HW_PHASE_ACTIVE)
    {
        object oPk = HW_SpawnPumpkin(HW_Scatter(GetLocation(oKing), 2.0, 5.0), "cursed");
        if (GetIsObjectValid(oPk))
        {
            ApplyEffectToObject(DURATION_TYPE_INSTANT,
                EffectVisualEffect(VFX_IMP_PULSE_FIRE), oPk);
            SpeakString("Grow, my pretties!");
        }
    }
    ExecuteScript("x2_def_endcombat", oKing);
}

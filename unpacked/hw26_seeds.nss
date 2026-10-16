// hw26_seeds - Bag of Pumpkin Seeds: plant a decorative jack-o'-lantern for 30
// minutes (10 charges, never refilled). Purely social: no guts, no aura.

#include "hw_inc"

void main()
{
    object oPC = OBJECT_SELF;
    if (!GetIsPC(oPC)) return;
    object oArea = GetArea(oPC);
    if (HW_AreaExcluded(GetResRef(oArea)))
    {
        SendMessageToPC(oPC, "Nothing will grow here.");
        return;
    }
    location l = GetLocalLocation(oPC, "hw_targloc");
    if (GetAreaFromLocation(l) != oArea) l = HW_Scatter(GetLocation(oPC), 1.5, 2.5);
    object oPk = CreateObject(OBJECT_TYPE_PLACEABLE, "hw_pumpkin" + IntToString(1 + Random(4)),
                              l, FALSE, HW_TAG_SEED);
    if (!GetIsObjectValid(oPk)) return;
    SetPlotFlag(oPk, TRUE);
    SetUseableFlag(oPk, FALSE);
    SetName(oPk, GetName(oPC) + "'s Jack-o'-Lantern");
    ApplyEffectToObject(DURATION_TYPE_PERMANENT,
        SupernaturalEffect(EffectVisualEffect(VFX_DUR_LIGHT_ORANGE_10)), oPk);
    ApplyEffectToObject(DURATION_TYPE_INSTANT, EffectVisualEffect(VFX_IMP_PULSE_FIRE), oPk);
    DestroyObject(oPk, 1800.0);
}

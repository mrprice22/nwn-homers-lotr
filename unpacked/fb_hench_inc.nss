//::///////////////////////////////////////////////
//:: fb_hench_inc -- Fell Beast companion helpers shared by horn_summon
//:: (dismiss-before-resummon) and mod_clientexit (dismiss on logout).
//:://////////////////////////////////////////////

const string FB_HENCH_TAG = "fellbeast_h";

// Remove any Fell Beast this PC already has out (mirrors MW_DismissActiveGuide).
void FB_DismissExisting(object oPC)
{
    int i;
    for (i = 1; i <= 5; i++)
    {
        object oH = GetHenchman(oPC, i);
        if (!GetIsObjectValid(oH)) break;
        if (GetTag(oH) == FB_HENCH_TAG)
        {
            RemoveHenchman(oPC, oH);
            AssignCommand(oH, ClearAllActions());
            ApplyEffectToObject(DURATION_TYPE_INSTANT, EffectDisappear(), oH);
        }
    }
}

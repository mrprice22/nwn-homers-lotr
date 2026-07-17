// q_shf_inc.nss -- Shifter initiation "The Second Skin"
// (roadmap: shifter-quest)
//
// The eleventh of the twelve prestige-order quests hung on Halmir the
// Grey (the prestige hub, prsg_inc.nss). Compact one-off, journal tag
// "pc_shifter".
//
// Flow: Halmir's Shifters branch (prsg_conv) offers the trial to a PC
// with 1+ Shifter level (CLASS_TYPE_SHIFTER = 35, verified in
// ovr/nwscript.nss; the hub line itself is already gated L16+ by the
// existing prsg_c_shift / PRSG_LVL_SHIFT). The trial: at Beorn's
// steading in the shadow of the Carrock lies a still pool where the
// master of the house drinks on four legs as often as two (existing
// placed instance 36 in beorn.git.json -- the zep_pool003 pool,
// retagged ShfBeornPool, made usable/dynamic/plot, its OnUsed now runs
// q_shf_pool; no script referenced the generic old tag "ZEP_POOL003").
// Look into the pool WEARING ANOTHER SKIN -- the roadmap-mandated
// form-lock condition: the attempt succeeds only while a polymorph
// effect is on the PC (wild shape, shifter shapes, any polymorph --
// QSHF_IsShifted loops the PC's effects for EFFECT_TYPE_POLYMORPH, the
// module's proven detection idiom from dmfi_dmw_inc.nss's
// dmwand_Untoad). Come in your true form and the attempt fails with a
// flavor message, nothing granted, retry allowed ("come wearing another
// skin, and look again"). Deterministic: no dice. Carry the tuft the
// pool gives back to Halmir; the induction consumes it and awards the
// Charm of the Carrock plus XP.
//
// Quest state is per-character and persistent via the prestige hub's
// campaign-DB stage idiom (prestigedb, order key "shift" -- see
// prsg_inc.nss): 0 none / 1 accepted / 2 tuft in hand / 3 done.
// One-off: stage 3 never resets. If the tuft is somehow lost at stage
// 2, looking into the pool again re-gives it (graceful, not farmable:
// the item is plot + cursed and only the finish consumes it).
//
// No new placements and no admin waypoint: the pool already stands at
// Beorn's homestead (placed instance 36 in beorn.git.json).

#include "prsg_inc"

const string QSHF_ORDER     = "shift";        // prestigedb stage key
const string QSHF_QUEST     = "pc_shifter";   // journal category tag
const string QSHF_TUFT_RES  = "q_shf_tuft";   // reagent blueprint
const string QSHF_TUFT_TAG  = "FirstSkinTuft";
const string QSHF_CHARM_RES = "q_shf_charm";  // reward blueprint
const string QSHF_CHARM_TAG = "CarrockCharm";

const int QSHF_XP = 1000;  // induction XP (L16-tier order)

// Stages (see header).
const int QSHF_STAGE_NONE     = 0;
const int QSHF_STAGE_ACCEPTED = 1;
const int QSHF_STAGE_TUFT     = 2;
const int QSHF_STAGE_DONE     = 3;

// TRUE if oPC has already worn another shape and come back whole
// (1+ Shifter level, CLASS_TYPE_SHIFTER = 35) -- the design gate.
int QSHF_IsShifter(object oPC)
{
    return PRSG_HasClass(oPC, CLASS_TYPE_SHIFTER);
}

// The turn-in reagent check: does oPC carry the tuft?
int QSHF_HasTuft(object oPC)
{
    return GetIsObjectValid(GetItemPossessedBy(oPC, QSHF_TUFT_TAG));
}

// The form-lock condition: TRUE while oPC wears another skin -- any
// polymorph effect is active on them (shifter shapes, druid wild shape,
// polymorph spells: all apply EffectPolymorph). Detection is the
// module's proven idiom (dmfi_dmw_inc.nss, dmwand_Untoad): loop the
// PC's effects for EFFECT_TYPE_POLYMORPH. Deterministic, no dice.
int QSHF_IsShifted(object oPC)
{
    effect e = GetFirstEffect(oPC);
    while (GetIsEffectValid(e))
    {
        if (GetEffectType(e) == EFFECT_TYPE_POLYMORPH) return TRUE;
        e = GetNextEffect(oPC);
    }
    return FALSE;
}

int QSHF_GetStage(object oPC)
{
    return PRSG_GetStage(oPC, QSHF_ORDER);
}

void QSHF_SetStage(object oPC, int nStage)
{
    PRSG_SetStage(oPC, QSHF_ORDER, nStage);
}

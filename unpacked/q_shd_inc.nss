// q_shd_inc.nss -- Shadowdancer initiation "The Unlit Deep"
// (roadmap: shadowdancer-quest)
//
// The fourth of the twelve prestige-order quests hung on Halmir the Grey
// (the prestige hub, prsg_inc.nss). Compact one-off, journal tag
// "pc_shadowdancer".
//
// Flow: Halmir's Shadowdancers branch (prsg_conv) offers the trial to a
// PC with 1+ Shadowdancer level (CLASS_TYPE_SHADOWDANCER = 27, verified
// in ovr/nwscript.nss -- the design gate; the hub line itself is visible
// from total level 11). The trial: deep in Moria, beside Balin's tomb,
// stands the Deep Well no plumb-line ever fathomed. Stand at its lip
// BEARING NO LIGHT -- the roadmap-mandated torch-suppression fail
// condition: no torch (or other light-property item) equipped, no active
// Light/Continual Flame spell effect. Come to the well lit and the trial
// fails that attempt (flavor message, nothing granted, retry allowed);
// come unlit and the deep leaves the Skein of the Unlit Deep in your
// hand (q_shd_skein, plot + cursed). Carry it back to Halmir; the
// induction awards the Boots of the Unlit Road plus XP and consumes the
// skein.
//
// Quest state is per-character and persistent via the prestige hub's
// campaign-DB stage idiom (prestigedb, order key "shadow" -- see
// prsg_inc.nss): 0 none / 1 accepted / 2 skein in hand / 3 done.
// One-off: stage 3 never resets. If the skein is somehow lost at stage 2,
// standing at the well unlit again re-gives it (graceful, not farmable:
// the item is plot + cursed and the finish consumes it from stage 2 only).
//
// No new placements and no admin waypoint: the Deep Well already stands
// beside Balin's tomb (existing placed instance in balinstomb.git.json,
// reused -- its instance OnUsed now runs q_shd_well, which chains the
// instance's previous OnUsed balintmb_dpwell, the well's sound flavor).

#include "prsg_inc"

const string QSHD_ORDER     = "shadow";           // prestigedb stage key
const string QSHD_QUEST     = "pc_shadowdancer";  // journal category tag
const string QSHD_SKEIN_RES = "q_shd_skein";      // reagent blueprint
const string QSHD_SKEIN_TAG = "ShadowSkein";
const string QSHD_BOOTS_RES = "q_shd_boots";      // reward blueprint
const string QSHD_BOOTS_TAG = "UnlitRoadBoots";

const int QSHD_XP = 1000;  // induction XP (L11-tier order)

// Stages (see header).
const int QSHD_STAGE_NONE     = 0;
const int QSHD_STAGE_ACCEPTED = 1;
const int QSHD_STAGE_SKEIN    = 2;
const int QSHD_STAGE_DONE     = 3;

int QSHD_GetStage(object oPC)
{
    return PRSG_GetStage(oPC, QSHD_ORDER);
}

void QSHD_SetStage(object oPC, int nStage)
{
    PRSG_SetStage(oPC, QSHD_ORDER, nStage);
}

// TRUE if oPC already walks unlit (1+ Shadowdancer level) -- the design
// gate for the trial.
int QSHD_IsShadow(object oPC)
{
    return PRSG_HasClass(oPC, CLASS_TYPE_SHADOWDANCER);
}

// The turn-in reagent check: does oPC carry the skein?
int QSHD_HasSkein(object oPC)
{
    return GetIsObjectValid(GetItemPossessedBy(oPC, QSHD_SKEIN_TAG));
}

// TRUE if oItem sheds light: a torch base item, or any item carrying the
// Light item property (magical glow -- includes Continual Flame cast on
// gear, which is stored as ITEM_PROPERTY_LIGHT).
int QSHD_ItemShedsLight(object oItem)
{
    if (!GetIsObjectValid(oItem)) return FALSE;
    if (GetBaseItemType(oItem) == BASE_ITEM_TORCH) return TRUE;

    itemproperty ip = GetFirstItemProperty(oItem);
    while (GetIsItemPropertyValid(ip))
    {
        if (GetItemPropertyType(ip) == ITEM_PROPERTY_LIGHT) return TRUE;
        ip = GetNextItemProperty(oItem);
    }
    return FALSE;
}

// The torch-suppression fail condition: TRUE if oPC carries any light --
// a torch or light-property item in ANY equipment slot (backpack items
// shed nothing), or an active Light / Continual Flame spell effect on
// their person. Darkvision sheds no light and does not count.
int QSHD_CarriesLight(object oPC)
{
    int nSlot;
    for (nSlot = 0; nSlot < NUM_INVENTORY_SLOTS; nSlot++)
    {
        if (QSHD_ItemShedsLight(GetItemInSlot(nSlot, oPC))) return TRUE;
    }

    effect eEff = GetFirstEffect(oPC);
    while (GetIsEffectValid(eEff))
    {
        int nSpell = GetEffectSpellId(eEff);
        if (nSpell == SPELL_LIGHT || nSpell == SPELL_CONTINUAL_FLAME)
            return TRUE;
        eEff = GetNextEffect(oPC);
    }
    return FALSE;
}

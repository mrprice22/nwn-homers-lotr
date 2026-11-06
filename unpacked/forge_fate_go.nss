// forge_fate_go.nss - "Aye, reforge it" (Loot Overhaul Phase 7, lo-fate-token).
//
// A Shard of Fate re-rolls the random affixes (LOOT_AFX_*) of the rolled item on
// the anvil: same loot level, rarity, base and look; forged enchantments, gem
// properties and sockets are kept.  Loot_Reforge (loot_inc) is transactional and
// bounded - the affixes fit the rarity's budget, the whole item stays within
// max(its value now, this forge's MODIFY_MAX) and the counted enchantments
// within max(its count now, MODIFY_MAX_PROPS).  The Shard is consumed ONLY after
// a committed reforge; every refusal keeps it.  Modelled on ForgeExpandDo
// (forge_inc).  The smith (OBJECT_SELF) speaks the outcome; the reply loops
// back to the forge menu.
#include "loot_inc"

void main()
{
    object oPC = GetPCSpeaker();
    if (!ForgeRefreshAnvilContext(oPC))
    {
        SpeakString("Lay a single piece upon my anvil first, and I will see what fate "
            + "it might have had.");
        return;
    }
    object oItem = GetLocalObject(oPC, "MODIFY_ITEM");
    if (!GetIsObjectValid(Loot_FindShard(oPC)))
    {
        SpeakString("To reforge the fate of the " + GetName(oItem) + " I must break a "
            + "Shard of Fate over it, and you carry none.");
        return;
    }
    string sOld = GetName(oItem);
    int nRes = Loot_Reforge(oItem, GetLocalInt(oPC, "MODIFY_MAX"),
                            GetLocalInt(oPC, "MODIFY_MAX_PROPS"), oPC);
    if (nRes == LOOT_FATE_NOT_ROLLED)
    {
        SpeakString("The " + sOld + " was made by a smith's hand, not drawn from fate. "
            + "There is nothing random in it for a Shard to change. Keep your Shard.");
        return;
    }
    if (nRes == LOOT_FATE_NAMED)
    {
        SpeakString("The " + sOld + " is a storied piece; its fate was written long ago "
            + "and a Shard cannot unwrite it. Keep your Shard.");
        return;
    }
    if (nRes == LOOT_FATE_NO_ROOM)
    {
        SpeakString("I have tried, but there is no room left in the " + sOld + " for "
            + "fate to work: what you have forged into it fills its weave. Keep your Shard.");
        return;
    }
    if (nRes != LOOT_FATE_OK)
    {
        SpeakString("Something in the " + sOld + " resists the Shard. I will not risk it. "
            + "Keep your Shard.");
        ForgeLog("fate: PC=" + GetName(oPC) + " item='" + sOld + "' refused, code "
            + IntToString(nRes));
        return;
    }
    Loot_SpendShard(oPC);
    // The staged-disenchant plan indexes the item's properties; they changed.
    ForgeStageClear(oPC);
    DeleteLocalInt(oPC, "FORGE_STG_PAGE");
    ForgeLog("fate: PC=" + GetName(oPC) + " item='" + sOld + "' -> '" + GetName(oItem) + "'");
    ForgeRefreshAnvilContext(oPC);
    ApplyEffectToObject(DURATION_TYPE_INSTANT, EffectVisualEffect(VFX_IMP_MAGBLUE), oPC);
    SpeakString("The Shard breaks across the anvil and its light runs into the metal. "
        + "What was the " + sOld + " is now the " + GetName(oItem) + ".");
}

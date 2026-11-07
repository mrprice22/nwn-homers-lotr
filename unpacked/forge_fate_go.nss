// forge_fate_go.nss - "Aye, reforge it" (Loot Overhaul Phase 7, lo-fate-token).
//
// A Shard of Fate re-rolls the random affixes (LOOT_AFX_*) of the rolled item on
// the anvil: same loot level, rarity, base and look; forged enchantments, gem
// properties and sockets are kept.  Loot_Reforge (loot_inc) is transactional and
// bounded by the plan Loot_FatePlan draws up: the affixes fit the rarity's
// budget, the whole item stays within max(its high-water value, this forge's
// MODIFY_MAX) and the counted enchantments within max(its high-water count,
// MODIFY_MAX_PROPS) - the high-water so one unlucky reforge can never shrink
// the next (lo-fate-ratchet).  The Shard is consumed ONLY after a committed
// reforge; every refusal keeps it and says which bound refused.  Every attempt
// is logged (server log + lootdb.loot_fate_log) by Loot_FateRecord.  The smith
// (OBJECT_SELF) speaks the outcome; the reply loops back to the forge menu.
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
    Loot_FateRecord(oPC, oItem, sOld, nRes);
    if (nRes != LOOT_FATE_OK)
    {
        SpeakString(Loot_FateRefusal(nRes, sOld, oPC));
        return;
    }
    Loot_SpendShard(oPC);
    // The staged-disenchant plan indexes the item's properties; they changed.
    ForgeStageClear(oPC);
    DeleteLocalInt(oPC, "FORGE_STG_PAGE");
    ForgeRefreshAnvilContext(oPC);
    ApplyEffectToObject(DURATION_TYPE_INSTANT, EffectVisualEffect(VFX_IMP_MAGBLUE), oPC);
    int nNow = GetLocalInt(oItem, "LOOT_AFX_N");
    int nKept = GetLocalInt(oPC, "LF_KEPTN");
    string s = "The Shard breaks across the anvil and its light runs into the metal. "
        + "What was the " + sOld + " is now the " + GetName(oItem) + ": fate gave it "
        + Loot_Count(nNow, "new enchantment");
    if (nKept > 0)
        s += ", and the other " + IntToString(nKept) + " are as they were";
    SpeakString(s + ".");
}

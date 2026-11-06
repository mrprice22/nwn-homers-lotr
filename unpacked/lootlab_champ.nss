// lootlab_champ.nss - Loot Lab: promote the nearest hostile creature to a
// champion (loot_champion.nss with LOOT_CHAMP_FORCE), skipping the chance roll
// but none of the eligibility rules - a boss, a natural elite, a summon or a
// plot creature still says no, and the admin is told why it might have.
// Roadmap: lo-creature-drops. Loot Lab action (emotewand.dlg Entry 19). See lootlab_inc.nss.
#include "lootlab_inc"

void main()
{
    object oPC = LL_Speaker();
    if (!LL_Authorised(oPC)) return;
    object oT = GetNearestCreature(CREATURE_TYPE_REPUTATION, REPUTATION_TYPE_ENEMY, oPC);
    if (!GetIsObjectValid(oT))
    {
        SendMessageToPC(oPC, "Loot Lab: no hostile creature in this area.");
        return;
    }
    if (GetLocalInt(oT, "LOOT_CHAMP"))
    {
        SendMessageToPC(oPC, "Loot Lab: " + GetName(oT) + " is already a champion.");
        return;
    }
    float fCR = GetChallengeRating(oT);
    int nHP = GetMaxHitPoints(oT);
    SetLocalInt(oT, "LOOT_CHAMP_FORCE", 1);
    ExecuteScript("loot_champion", oT);
    if (GetLocalInt(oT, "LOOT_CHAMP"))
        SendMessageToPC(oPC, "Loot Lab: " + GetName(oT) + " is now a champion: HP "
            + IntToString(nHP) + " -> " + IntToString(GetMaxHitPoints(oT)) + ", CR "
            + IntToString(FloatToInt(fCR)) + " -> " + IntToString(FloatToInt(GetChallengeRating(oT))) + ".");
    else
        SendMessageToPC(oPC, "Loot Lab: " + GetName(oT) + " cannot be a champion (a boss, a natural"
            + " elite, a summon, plot/immortal, an excluded or non-hostile creature, or LOOT_NONE).");
}

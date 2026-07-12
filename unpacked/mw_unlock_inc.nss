//::///////////////////////////////////////////////
//:: mw_unlock_inc -- MeaningWave guide roster, persistence, and summoning.
//::
//:: Per-PC unlock flags live in the "meaningwave" campaign DB (scoped per
//:: player by passing oPC to GetCampaignInt/SetCampaignInt). Roster is
//:: 7 named figures plus Akira the Don as Hall curator.
//::
//:: Meta-quest stages on "MW Path of Meaning":
//::   1 = intro whisper (added on first shrine touch or guide encounter)
//::   2..8 = stage advances as guides 1..7 are unlocked
//::   9 = finale (added by Akira's dialogue when mixtape is granted)
//:://////////////////////////////////////////////

#include "x2_inc_itemprop"

const string MW_DB         = "meaningwave";
const string MW_META_QUEST = "MW Path of Meaning";
const int    MW_ROSTER_SIZE = 7;

string MW_GuideAt(int i)
{
    switch (i)
    {
        case 0: return "peterson";
        case 1: return "watts";
        case 2: return "campbell";
        case 3: return "mckenna";
        case 4: return "jocko";
        case 5: return "jung";
        case 6: return "aurelius";
    }
    return "";
}

string MW_GuideDisplayName(string sGuide)
{
    if (sGuide == "peterson")  return "Jordan Peterson";
    if (sGuide == "watts")     return "Alan Watts";
    if (sGuide == "campbell")  return "Joseph Campbell";
    if (sGuide == "mckenna")   return "Terence McKenna";
    if (sGuide == "jocko")     return "Jocko Willink";
    if (sGuide == "jung")      return "Carl Jung";
    if (sGuide == "aurelius")  return "Marcus Aurelius";
    return sGuide;
}

string MW_GuideQuestTag(string sGuide)
{
    return "MW " + MW_GuideDisplayName(sGuide);
}

int MW_IsUnlocked(object oPC, string sGuide)
{
    return GetCampaignInt(MW_DB, "u_" + sGuide, oPC);
}

// Derive the guide name ("jocko", "aurelius", ...) from the world NPC's tag,
// which follows the "mw_<guide>_w" convention. Call from a dialogue script where
// OBJECT_SELF is the guide NPC. Lets every quiz script stay generic (no per-NPC
// copies). Returns "" if the tag does not match the pattern.
string MW_GuideFromTag()
{
    string sTag = GetTag(OBJECT_SELF);
    int nLen = GetStringLength(sTag);
    if (nLen <= 5) return "";                       // needs "mw_" + name + "_w"
    if (GetStringLeft(sTag, 3) != "mw_") return "";
    if (GetStringRight(sTag, 2) != "_w") return "";
    return GetSubString(sTag, 3, nLen - 5);         // strip "mw_" and "_w"
}

int MW_UnlockCount(object oPC)
{
    int n = 0;
    int i;
    for (i = 0; i < MW_ROSTER_SIZE; i++)
        if (MW_IsUnlocked(oPC, MW_GuideAt(i))) n++;
    return n;
}

void MW_IntroJournal(object oPC)
{
    if (GetCampaignInt(MW_DB, "jq_intro", oPC)) return;
    SetCampaignInt(MW_DB, "jq_intro", 1, oPC);
    AddJournalQuestEntry(MW_META_QUEST, 1, oPC, FALSE, FALSE);
}

void MW_EncounterJournal(object oPC, string sGuide)
{
    MW_IntroJournal(oPC);
    if (MW_IsUnlocked(oPC, sGuide)) return;
    string sKey = "jq_enc_" + sGuide;
    if (GetCampaignInt(MW_DB, sKey, oPC)) return;
    SetCampaignInt(MW_DB, sKey, 1, oPC);
    AddJournalQuestEntry(MW_GuideQuestTag(sGuide), 1, oPC, FALSE, FALSE);
}

void MW_SyncJournal(object oPC)
{
    int nCount = MW_UnlockCount(oPC);
    if (nCount == 0) return;
    AddJournalQuestEntry(MW_META_QUEST, 1, oPC, FALSE, FALSE);
    AddJournalQuestEntry(MW_META_QUEST, nCount + 1, oPC, FALSE, FALSE);
    if (GetCampaignInt(MW_DB, "finale", oPC))
        AddJournalQuestEntry(MW_META_QUEST, MW_ROSTER_SIZE + 2, oPC, FALSE, FALSE);
    int i;
    for (i = 0; i < MW_ROSTER_SIZE; i++)
    {
        string sGuide = MW_GuideAt(i);
        if (MW_IsUnlocked(oPC, sGuide))
            AddJournalQuestEntry(MW_GuideQuestTag(sGuide), 2, oPC, FALSE, FALSE);
    }
}

void MW_Unlock(object oPC, string sGuide)
{
    if (MW_IsUnlocked(oPC, sGuide)) return;
    SetCampaignInt(MW_DB, "u_" + sGuide, 1, oPC);

    int nCount = MW_UnlockCount(oPC);

    AddJournalQuestEntry(MW_META_QUEST, nCount + 1, oPC, TRUE, FALSE);
    AddJournalQuestEntry(MW_GuideQuestTag(sGuide), 2, oPC, TRUE, FALSE);

    FloatingTextStringOnCreature(
        "You have gained the wisdom of " + MW_GuideDisplayName(sGuide) +
        ". Rest to summon them as a guide.",
        oPC, FALSE);

    GiveXPToCreature(oPC, 500);
    ApplyEffectToObject(DURATION_TYPE_INSTANT,
        EffectVisualEffect(VFX_IMP_HEALING_X), oPC);
}

void MW_DismissActiveGuide(object oPC)
{
    int i;
    for (i = 1; i <= 5; i++)
    {
        object oH = GetHenchman(oPC, i);
        if (!GetIsObjectValid(oH)) break;
        if (GetStringLeft(GetTag(oH), 3) == "mw_")
        {
            RemoveHenchman(oPC, oH);
            AssignCommand(oH, ClearAllActions());
            ApplyEffectToObject(DURATION_TYPE_INSTANT,
                EffectDisappear(), oH);
        }
    }
    DeleteLocalString(oPC, "mw_current");
}

// Map a flat damage amount (+N) to its iprp_damagecost.2da row index.
// This module's hak extends the table to +20 (rows 21..30 = +11..+20), so we
// pass the raw row index rather than the stock IP_CONST_DAMAGEBONUS_* constants
// (which only reach +10). Layout: +1..+5 = rows 1..5; +6..+20 = rows 16..30.
int MW_DmgBonusConst(int n)
{
    if (n < 1)  n = 1;
    if (n > 20) n = 20;     // hak maximum is +20
    if (n <= 5) return n;   // rows 1..5   -> +1..+5
    return n + 10;          // rows 16..30 -> +6..+20
}

// Add scaled +divine / +positive damage to a weapon (or unarmed gloves/bracers).
void MW_AddWeaponDamage(object oItem, int nDivine, int nPositive)
{
    if (!GetIsObjectValid(oItem)) return;
    IPSafeAddItemProperty(oItem,
        ItemPropertyDamageBonus(IP_CONST_DAMAGETYPE_DIVINE,   MW_DmgBonusConst(nDivine)));
    IPSafeAddItemProperty(oItem,
        ItemPropertyDamageBonus(IP_CONST_DAMAGETYPE_POSITIVE, MW_DmgBonusConst(nPositive)));
}

// Ward the aegis ring against a single damage type: +15/- resist & 25% immunity.
void MW_WardRing(object oRing, int nType)
{
    IPSafeAddItemProperty(oRing,
        ItemPropertyDamageResistance(nType, IP_CONST_DAMAGERESIST_15));
    IPSafeAddItemProperty(oRing,
        ItemPropertyDamageImmunity(nType, IP_CONST_DAMAGEIMMUNITY_25_PERCENT));
}

// Scale a freshly-summoned guide by how many MeaningWave figures oPC has unlocked.
// Re-summoning makes a fresh CreateObject, so these bonuses never stack across summons.
void MW_ScaleGuide(object oGuide, object oPC)
{
    int nCount = MW_UnlockCount(oPC);
    if (nCount < 1) nCount = 1; // you must own a guide to summon it

    // --- Aegis ring: resistance + immunity to every damage type ---
    object oRing = GetItemInSlot(INVENTORY_SLOT_LEFTRING, oGuide);
    if (GetIsObjectValid(oRing))
    {
        MW_WardRing(oRing, IP_CONST_DAMAGETYPE_BLUDGEONING);
        MW_WardRing(oRing, IP_CONST_DAMAGETYPE_PIERCING);
        MW_WardRing(oRing, IP_CONST_DAMAGETYPE_SLASHING);
        MW_WardRing(oRing, IP_CONST_DAMAGETYPE_MAGICAL);
        MW_WardRing(oRing, IP_CONST_DAMAGETYPE_ACID);
        MW_WardRing(oRing, IP_CONST_DAMAGETYPE_COLD);
        MW_WardRing(oRing, IP_CONST_DAMAGETYPE_DIVINE);
        MW_WardRing(oRing, IP_CONST_DAMAGETYPE_ELECTRICAL);
        MW_WardRing(oRing, IP_CONST_DAMAGETYPE_FIRE);
        MW_WardRing(oRing, IP_CONST_DAMAGETYPE_NEGATIVE);
        MW_WardRing(oRing, IP_CONST_DAMAGETYPE_POSITIVE);
        MW_WardRing(oRing, IP_CONST_DAMAGETYPE_SONIC);
    }

    // --- Ability scaling: +6 to every ability per unlocked guide ---
    // Stacked supernatural effects bypass the per-effect cap, so this is uncapped.
    int i;
    for (i = 0; i < nCount; i++)
    {
        int a;
        for (a = ABILITY_STRENGTH; a <= ABILITY_CHARISMA; a++)
            ApplyEffectToObject(DURATION_TYPE_PERMANENT,
                SupernaturalEffect(EffectAbilityIncrease(a, 6)), oGuide);
    }

    // --- Weapon scaling: +2 divine & +2 positive damage per unlocked guide ---
    int nDmg = 2 * nCount;
    object oWpnR = GetItemInSlot(INVENTORY_SLOT_RIGHTHAND, oGuide);
    object oWpnL = GetItemInSlot(INVENTORY_SLOT_LEFTHAND,  oGuide);
    int bArmed = FALSE;
    if (GetIsObjectValid(oWpnR)) { MW_AddWeaponDamage(oWpnR, nDmg, nDmg); bArmed = TRUE; }
    if (GetIsObjectValid(oWpnL)) { MW_AddWeaponDamage(oWpnL, nDmg, nDmg); bArmed = TRUE; }
    if (!bArmed)
    {
        // Unarmed monks (Watts, Jocko): bonus rides on their gloves/bracers.
        object oArms = GetItemInSlot(INVENTORY_SLOT_ARMS, oGuide);
        MW_AddWeaponDamage(oArms, nDmg, nDmg);
    }

    // --- Small Spellcraft top-up for the Counterspell combat mode -- most of
    // --- the per-guide variance now comes from each blueprint's base Rank ---
    ApplyEffectToObject(DURATION_TYPE_PERMANENT,
        SupernaturalEffect(EffectSkillIncrease(SKILL_SPELLCRAFT, 5)), oGuide);
}

void MW_SummonGuide(object oPC, string sGuide)
{
    if (!MW_IsUnlocked(oPC, sGuide))
    {
        FloatingTextStringOnCreature(
            MW_GuideDisplayName(sGuide) + " is not yet known to you.",
            oPC, FALSE);
        return;
    }
    MW_DismissActiveGuide(oPC);

    location lLoc = GetLocation(oPC);
    object oGuide = CreateObject(OBJECT_TYPE_CREATURE,
        "mw_" + sGuide, lLoc);
    if (!GetIsObjectValid(oGuide))
    {
        FloatingTextStringOnCreature(
            "Failed to summon " + MW_GuideDisplayName(sGuide) +
            " (blueprint mw_" + sGuide + " missing).",
            oPC, FALSE);
        return;
    }
    AddHenchman(oPC, oGuide);
    SetLocalString(oPC, "mw_current", sGuide);
    ApplyEffectToObject(DURATION_TYPE_INSTANT,
        EffectVisualEffect(VFX_FNF_SUMMON_MONSTER_3), oGuide);

    // Scale gear/stats to the number of guides oPC has unlocked, and apply the
    // aegis ring's resistance/immunity to the freshly-equipped instance.
    MW_ScaleGuide(oGuide, oPC);
}

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
}

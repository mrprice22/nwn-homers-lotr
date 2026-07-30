//::///////////////////////////////////////////////
//:: sk_probe_inc
//:: "Spells known" probe for levels 41-60 -- a diagnostic, not a game system.
//::
//:: Players report that casters learn no new spells past level 40 (roadmap
//:: legendary-caster-spells-on-level-up). Slots per day are fixed by the
//:: hak_2da/cls_spgn_*.2da tables, but *spells known* is a separate question and
//:: the answer decides whether any further work is needed at all:
//::
//::   - The NWNX MaxLevel readme lists "Spellcasters may not change spells when
//::     levelling up" as a known issue, and says there is "no client interface for
//::     PCs to change their known spells past level 40".
//::   - Nothing server-side can reopen that page: the wizard's 2-free-spells-per-
//::     level count is engine-side (Wizard has no SpellKnownTable and ruleset.2da
//::     does not expose it), and NWNX_ON_CLIENT_LEVEL_UP_BEGIN_* carries no data.
//::   - But nobody has ever *measured* it on this build (8193.37.17).
//::
//:: So this measures it, from real play rather than a lab test: snapshot the known
//:: spell counts before a level up, diff them after, and report the delta. If a
//:: wizard crossing 43 -> 44 gains 2 known spells, the native GUI works and there
//:: is nothing left to build. If it gains 0, the native path is genuinely closed
//:: and a scripted grant (NWNX_Creature_AddKnownSpell) is the only remaining
//:: option.
//::
//:: Only Wizard, Sorcerer and Bard are probed: GetKnownSpellCount() requires a
//:: SpellbookRestricted class, and per classes.2da those are exactly the three.
//:: Cleric/Druid/Paladin/Ranger know their whole list and have nothing to pick.
//::
//:: Reported to the levelling player only if they are an admin (Admin_CanAdmin),
//:: plus a log line either way. The log line is the belt-and-braces copy: this
//:: server runs containerized and does not reliably flush script logs, which is
//:: why the chat message exists at all.
//::
//:: Hooked from sk_probe_pre.nss (NWNX_ON_LEVEL_UP_BEFORE) and sk_probe_post.nss
//:: (NWNX_ON_LEVEL_UP_AFTER), both subscribed in onmoduleload.nss. Remove all
//:: three files and the two subscriptions once the question is answered.
//:://////////////////////////////////////////////

#include "admin_db"

// Levels below this are stock and known-good -- do not spend cycles or spam.
const int SK_FIRST_LEVEL = 39;

// Store the current known-spell counts on oPC so the AFTER handler can diff them.
void SK_Snapshot(object oPC);

// Diff against the snapshot and report what the level up actually granted.
void SK_ReportDelta(object oPC);


// The three SpellbookRestricted classes, by probe index 0-2.
int SK_ProbeClass(int nIndex)
{
    switch (nIndex)
    {
        case 0: return CLASS_TYPE_WIZARD;
        case 1: return CLASS_TYPE_SORCERER;
        case 2: return CLASS_TYPE_BARD;
    }
    return CLASS_TYPE_INVALID;
}

string SK_ClassName(int nClass)
{
    switch (nClass)
    {
        case CLASS_TYPE_WIZARD:   return "Wizard";
        case CLASS_TYPE_SORCERER: return "Sorcerer";
        case CLASS_TYPE_BARD:     return "Bard";
    }
    return "?";
}

// Bard tops out at spell level 6; wizard and sorcerer go to 9.
int SK_TopSpellLevel(int nClass)
{
    return (nClass == CLASS_TYPE_BARD) ? 6 : 9;
}

string SK_VarName(int nClass, int nSpellLevel)
{
    return "SK_PROBE_" + IntToString(nClass) + "_" + IntToString(nSpellLevel);
}


void SK_Snapshot(object oPC)
{
    if (!GetIsPC(oPC) || GetIsDM(oPC)) return;
    if (GetHitDice(oPC) < SK_FIRST_LEVEL) return;

    int i;
    for (i = 0; i < 3; i++)
    {
        int nClass = SK_ProbeClass(i);
        if (GetLevelByClass(nClass, oPC) < 1) continue;

        int nTop = SK_TopSpellLevel(nClass);
        int nSpellLevel;
        for (nSpellLevel = 0; nSpellLevel <= nTop; nSpellLevel++)
        {
            // +1 so a stored 0 is distinguishable from "never snapshotted".
            SetLocalInt(oPC, SK_VarName(nClass, nSpellLevel),
                        GetKnownSpellCount(oPC, nClass, nSpellLevel) + 1);
        }
    }
}


void SK_ReportDelta(object oPC)
{
    if (!GetIsPC(oPC) || GetIsDM(oPC)) return;

    int nLevel = GetHitDice(oPC);
    if (nLevel <= SK_FIRST_LEVEL) return;

    int i;
    for (i = 0; i < 3; i++)
    {
        int nClass = SK_ProbeClass(i);
        int nClassLevel = GetLevelByClass(nClass, oPC);
        if (nClassLevel < 1) continue;

        int nTop = SK_TopSpellLevel(nClass);
        int nTotal = 0;
        string sPerLevel = "";
        int nSpellLevel;

        for (nSpellLevel = 0; nSpellLevel <= nTop; nSpellLevel++)
        {
            string sVar = SK_VarName(nClass, nSpellLevel);
            int nBefore = GetLocalInt(oPC, sVar);
            DeleteLocalInt(oPC, sVar);
            if (nBefore == 0) continue;         // no snapshot for this spell level
            nBefore = nBefore - 1;              // undo the +1 sentinel offset

            int nAfter = GetKnownSpellCount(oPC, nClass, nSpellLevel);
            int nDelta = nAfter - nBefore;
            nTotal = nTotal + nDelta;

            if (nDelta != 0)
            {
                sPerLevel = sPerLevel + " L" + IntToString(nSpellLevel) + ":"
                          + (nDelta > 0 ? "+" : "") + IntToString(nDelta);
            }
        }

        string sMsg = "[spells-known probe] " + SK_ClassName(nClass) + " "
                    + IntToString(nClassLevel) + " (character " + IntToString(nLevel)
                    + "): " + IntToString(nTotal) + " new spell(s) known";
        if (sPerLevel != "") sMsg = sMsg + " --" + sPerLevel;

        WriteTimestampedLogEntry(sMsg + " [" + GetName(oPC) + "]");
        if (Admin_CanAdmin(oPC)) SendMessageToPC(oPC, sMsg);
    }
}

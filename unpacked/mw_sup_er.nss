//:: mw_sup_er -- OnEndCombatRound for Campbell (Bard) and McKenna (Druid).
//::
//:: MW_STYLE 0 (Balanced, default):
//::   Heal party at < 25% HP; otherwise let standard AI decide.
//::
//:: MW_STYLE 1 (Combat):
//::   Cast offensive spells at nearest enemy; only emergency-heal at < 15% HP.
//::
//:: MW_STYLE 2 (Healer):
//::   Heal party at < 50% HP; cast Haste on the master if no one needs healing.

const int SPELL_HEAL_ID  = 79;
const int SPELL_CCW      = 31;
const int SPELL_CSW      = 35;
// SPELL_HASTE(78), FEAT_BARD_SONGS(257), FEAT_CURSE_SONG(871) from nwscript.nss
// Bard offensive options
const int SPELL_DOMINATE = 45;
const int SPELL_HOLD_P   = 80;
// Druid offensive
const int SPELL_STORM    = 173;

object FindHurt(float fRatio)
{
    object oPC = GetMaster();
    if (!GetIsObjectValid(oPC)) return OBJECT_INVALID;
    if (GetCurrentHitPoints(oPC) < FloatToInt(IntToFloat(GetMaxHitPoints(oPC)) * fRatio))
        return oPC;
    int i;
    for (i = 1; i <= 5; i++)
    {
        object oH = GetHenchman(oPC, i);
        if (!GetIsObjectValid(oH)) break;
        if (oH == OBJECT_SELF) continue;
        if (GetCurrentHitPoints(oH) < FloatToInt(IntToFloat(GetMaxHitPoints(oH)) * fRatio))
            return oH;
    }
    return OBJECT_INVALID;
}

void main()
{
    int nStyle = GetLocalInt(OBJECT_SELF, "MW_STYLE");
    object oEnemy = GetNearestCreature(CREATURE_TYPE_REPUTATION, REPUTATION_TYPE_ENEMY, OBJECT_SELF, 1, CREATURE_TYPE_IS_ALIVE, TRUE);

    if (nStyle == 1) // Combat: attack first, emergency heal only
    {
        object oEmergency = FindHurt(0.15f);
        if (GetIsObjectValid(oEmergency) && GetHasSpell(SPELL_HEAL_ID, OBJECT_SELF))
        {
            ActionCastSpellAtObject(SPELL_HEAL_ID, oEmergency);
        }
        else if (GetIsObjectValid(oEnemy))
        {
            // Curse Song debuffs enemies (bards only -- no-ops for Druid)
            if (GetHasFeat(FEAT_CURSE_SONG))
                ActionUseFeat(FEAT_CURSE_SONG, OBJECT_SELF);
            if (GetHasSpell(SPELL_STORM, OBJECT_SELF))
                ActionCastSpellAtObject(SPELL_STORM, oEnemy);
            else if (GetHasSpell(SPELL_DOMINATE, OBJECT_SELF))
                ActionCastSpellAtObject(SPELL_DOMINATE, oEnemy);
            else if (GetHasSpell(SPELL_HOLD_P, OBJECT_SELF))
                ActionCastSpellAtObject(SPELL_HOLD_P, oEnemy);
        }
        ExecuteScript("x2_def_endcombat", OBJECT_SELF);
        return;
    }

    if (nStyle == 2) // Healer: keep party alive
    {
        object oHurt = FindHurt(0.50f);
        if (GetIsObjectValid(oHurt))
        {
            if (GetHasSpell(SPELL_HEAL_ID, OBJECT_SELF))
                ActionCastSpellAtObject(SPELL_HEAL_ID, oHurt);
            else if (GetHasSpell(SPELL_CCW, OBJECT_SELF))
                ActionCastSpellAtObject(SPELL_CCW, oHurt);
            else if (GetHasSpell(SPELL_CSW, OBJECT_SELF))
                ActionCastSpellAtObject(SPELL_CSW, oHurt);
        }
        else
        {
            object oPC = GetMaster();
            if (GetIsObjectValid(oPC) && GetHasSpell(SPELL_HASTE, OBJECT_SELF) &&
                !GetHasSpellEffect(SPELL_HASTE, oPC))
                ActionCastSpellAtObject(SPELL_HASTE, oPC);
        }
        // Bard song keeps party buffed; no-ops on Druid. x2 won't run in this mode.
        if (GetHasFeat(FEAT_BARD_SONGS))
            ActionUseFeat(FEAT_BARD_SONGS, OBJECT_SELF);
        return; // Healer does not fall through to standard attack AI
    }

    // Style 0 (Balanced): heal at < 25%, else standard AI
    object oHurt = FindHurt(0.25f);
    if (GetIsObjectValid(oHurt))
    {
        if (GetHasSpell(SPELL_HEAL_ID, OBJECT_SELF))
            ActionCastSpellAtObject(SPELL_HEAL_ID, oHurt);
        else if (GetHasSpell(SPELL_CCW, OBJECT_SELF))
            ActionCastSpellAtObject(SPELL_CCW, oHurt);
    }

    ExecuteScript("x2_def_endcombat", OBJECT_SELF);
}

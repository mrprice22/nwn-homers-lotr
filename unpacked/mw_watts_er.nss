//:: mw_watts_er -- OnEndCombatRound for Watts (Cleric 30 / Monk 30).
//::
//:: MW_STYLE 0 (Enlightened, default):
//::   Heal party members below 50% HP; buff self with Divine Power if missing;
//::   otherwise standard AI handles combat.
//::
//:: MW_STYLE 1 (Guardian):
//::   Pure support -- heal anyone below 70% HP; cast party buffs when healthy.
//::   Does not attack.
//::
//:: MW_STYLE 2 (Zen Strike):
//::   Buff self with Divine Power; use Quivering Palm on the strongest foe;
//::   fall through to standard AI for basic attacks and support.

const int SPELL_HEAL_ID        = 79;
const int SPELL_CCW            = 31;
const int SPELL_CSW            = 35;
// SPELL_DIVINE_POWER(42), SPELL_BLESS(6), SPELL_PRAYER(133) from nwscript.nss
const int FEAT_QUIV_PALM       = 296;
const int FEAT_STUN_FIST       = 39;

// Return the first party member (master + henchmen) below fRatio of max HP.
// Returns OBJECT_INVALID if everyone is healthy.
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

    if (nStyle == 1) // Guardian: pure healing/support
    {
        object oHurt = FindHurt(0.70f);
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
            // Party healthy -- layer buffs
            if (GetHasSpell(SPELL_PRAYER, OBJECT_SELF) &&
                !GetHasSpellEffect(SPELL_PRAYER, OBJECT_SELF))
                ActionCastSpellAtObject(SPELL_PRAYER, OBJECT_SELF);
            else if (GetHasSpell(SPELL_BLESS, OBJECT_SELF) &&
                     !GetHasSpellEffect(SPELL_BLESS, OBJECT_SELF))
                ActionCastSpellAtObject(SPELL_BLESS, OBJECT_SELF);
        }
        return; // Guardian never falls through to standard combat AI
    }

    if (nStyle == 2) // Zen Strike: buff then melee
    {
        if (GetHasSpell(SPELL_DIVINE_POWER, OBJECT_SELF) &&
            !GetHasSpellEffect(SPELL_DIVINE_POWER, OBJECT_SELF))
        {
            ActionCastSpellAtObject(SPELL_DIVINE_POWER, OBJECT_SELF);
            // Fall through so x2 also attacks this round.
        }
        object oEnemy = GetNearestCreature(CREATURE_TYPE_REPUTATION, REPUTATION_TYPE_ENEMY, OBJECT_SELF, 1, CREATURE_TYPE_IS_ALIVE, TRUE);
        if (GetIsObjectValid(oEnemy))
        {
            if (GetHasFeat(FEAT_QUIV_PALM))
                ActionUseFeat(FEAT_QUIV_PALM, oEnemy);
            else if (GetHasFeat(FEAT_STUN_FIST))
                ActionUseFeat(FEAT_STUN_FIST, oEnemy);
        }
        ExecuteScript("x2_def_endcombat", OBJECT_SELF);
        return;
    }

    // Style 0 (Enlightened): heal first, then self-buff, then standard AI
    object oHurt = FindHurt(0.50f);
    if (GetIsObjectValid(oHurt))
    {
        if (GetHasSpell(SPELL_HEAL_ID, OBJECT_SELF))
            ActionCastSpellAtObject(SPELL_HEAL_ID, oHurt);
        else if (GetHasSpell(SPELL_CCW, OBJECT_SELF))
            ActionCastSpellAtObject(SPELL_CCW, oHurt);
    }
    else if (GetHasSpell(SPELL_DIVINE_POWER, OBJECT_SELF) &&
             !GetHasSpellEffect(SPELL_DIVINE_POWER, OBJECT_SELF))
    {
        ActionCastSpellAtObject(SPELL_DIVINE_POWER, OBJECT_SELF);
    }

    ExecuteScript("x2_def_endcombat", OBJECT_SELF);
}

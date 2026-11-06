// loot_champion - Loot Overhaul Phase 4: maybe promote a freshly spawned creature
// to a CHAMPION (Diablo-style).  OBJECT_SELF = the creature.
//
// Run once per creature by bst_install (which every OnSpawn reaches, with the
// leash OnEnter as a safety net), and by the Loot Lab's "make the nearest
// hostile a champion" (which sets LOOT_CHAMP_FORCE first).
//
// Candidates: a normal creature in a hostile faction - never a PC/DM, a summon
// or henchman (any master), plot or immortal, a registered boss, a natural
// elite, an `exclude`-listed creature, or one carrying LOOT_NONE / LOOT_NO_CHAMP.
// Chance: per mille, per area (Loot_AreaChampion; lower where the area already
// has natural elites).  All numbers: loot/sources.json creatures.champions.
//
// A champion gets a fixed power buff and an honest CR:
//   * name "<prefix> <name>" (the base name is kept in LOOT_CHAMP_NAME for the
//     bestiary messages), a glow;
//   * LOOTD_CHAMP_HP_PCT % more max hit points;
//   * +AC (dodge) and +saves, supernatural (cannot be dispelled);
//   * +attack and +damage through the bonus pool (BPOOL_SRC_CHAMP) - never a
//     raw EffectAttackIncrease, which would suppress every pooled bonus;
//   * CR raised by what the toolset's CR formula pays for the extra HP (the
//     formula's hit-point term, nwn_manager bin/nwn_wiki/cr.py), so kill XP and
//     the drop's loot level follow.  The base CR is kept in LOOT_CHAMP_BASECR.
// Its drop uses the elite chance (loot_ondeath reads LOOT_CHAMP); the bestiary
// counts it under the base creature, plus a champion tally.

#include "loot_inc"
#include "nwnx_creature"
#include "nwnx_object"
#include "bonus_pool_inc"

// The toolset CR formula's hit-point term, per hit point:
//   0.2 * HD * (walk rate / PC walk rate) / average class HP * race CRModifier
// WalkRate 7 ("Default") takes the appearance's MOVERATE, as the toolset does.
float LootC_HpSlope(object oCre)
{
    float fAvg = 0.0;
    int i;
    for (i = 1; i <= 3; i++)
    {
        int nCls = GetClassByPosition(i, oCre);
        if (nCls == CLASS_TYPE_INVALID) continue;
        int nDie = StringToInt(Get2DAString("classes", "HitDie", nCls));
        if (nDie <= 0) nDie = 8;
        fAvg += IntToFloat(GetLevelByPosition(i, oCre)) * IntToFloat(nDie + 1) / 2.0;
    }
    if (fAvg <= 0.0) return 0.0;

    float fPc = StringToFloat(Get2DAString("creaturespeed", "WALKRATE", 0));
    if (fPc <= 0.0) fPc = 2.0;
    float fWalk = 1.75;                                  // NORM
    int nRate = GetMovementRate(oCre);
    if (nRate == 7)
    {
        string sMove = GetStringUpperCase(Get2DAString("appearance", "MOVERATE",
                                                       GetAppearanceType(oCre)));
        int r;
        for (r = 0; r <= 8; r++)
            if (GetStringUpperCase(Get2DAString("creaturespeed", "2DAName", r)) == sMove)
            {
                fWalk = StringToFloat(Get2DAString("creaturespeed", "WALKRATE", r));
                break;
            }
    }
    else
        fWalk = StringToFloat(Get2DAString("creaturespeed", "WALKRATE", nRate));

    float fMod = StringToFloat(Get2DAString("racialtypes", "CRModifier", GetRacialType(oCre)));
    if (fMod <= 0.0) fMod = 1.0;
    return 0.2 * IntToFloat(GetHitDice(oCre)) * (fWalk / fPc) / fAvg * fMod;
}

int LootC_IsCandidate(object oCre)
{
    if (GetObjectType(oCre) != OBJECT_TYPE_CREATURE) return FALSE;
    if (GetIsPC(oCre) || GetIsDM(oCre) || GetIsDead(oCre)) return FALSE;
    if (GetLocalInt(oCre, "LOOT_CHAMP")) return FALSE;            // already one
    if (GetLocalInt(oCre, "LOOT_NONE") || GetLocalInt(oCre, "LOOT_NO_CHAMP")) return FALSE;
    if (GetIsObjectValid(GetMaster(oCre))) return FALSE;          // summons, henchmen
    if (GetPlotFlag(oCre) || GetImmortal(oCre)) return FALSE;
    string sRes = GetResRef(oCre);
    if (LootD_IsBoss(sRes)) return FALSE;
    if (LootD_CreatureListed(sRes) == LOOTD_LIST_NEVER) return FALSE;
    if (!LootD_IsHostileFaction(NWNX_Creature_GetFaction(oCre))) return FALSE;
    if (Loot_IsNaturalElite(oCre)) return FALSE;
    return TRUE;
}

void LootC_Promote(object oCre)
{
    float fCR = GetChallengeRating(oCre);
    string sName = GetName(oCre);
    SetLocalInt(oCre, "LOOT_CHAMP", 1);
    SetLocalString(oCre, "LOOT_CHAMP_NAME", sName);
    SetLocalFloat(oCre, "LOOT_CHAMP_BASECR", fCR);
    SetName(oCre, LOOTD_CHAMP_PREFIX + " " + sName);

    int nMax = GetMaxHitPoints(oCre);
    int nAdd = nMax * LOOTD_CHAMP_HP_PCT / 100;
    if (nAdd > 0)
    {
        NWNX_Object_SetMaxHitPoints(oCre, nMax + nAdd);
        NWNX_Object_SetCurrentHitPoints(oCre, nMax + nAdd);
    }

    effect e = EffectACIncrease(LOOTD_CHAMP_AC, AC_DODGE_BONUS);
    e = EffectLinkEffects(e, EffectSavingThrowIncrease(SAVING_THROW_ALL, LOOTD_CHAMP_SAVES));
    e = EffectLinkEffects(e, EffectVisualEffect(VFX_DUR_GLOW_LIGHT_RED));
    e = TagEffect(SupernaturalEffect(e), "LOOT_CHAMP");
    ApplyEffectToObject(DURATION_TYPE_PERMANENT, e, oCre);
    BPool_Set(oCre, BPOOL_CH_ATTACK, BPOOL_SRC_CHAMP, LOOTD_CHAMP_AB);
    BPool_Set(oCre, BPOOL_CH_DAMAGE, BPOOL_SRC_CHAMP, LOOTD_CHAMP_DAMAGE);

    // The CR the toolset would compute for the buffed creature: the stored CR
    // plus the formula's hit-point term for the added HP.  Whole numbers from 1
    // up, as the toolset stores them.
    float fNew = fCR + LootC_HpSlope(oCre) * IntToFloat(nAdd);
    if (fNew >= 1.0) fNew = IntToFloat(FloatToInt(fNew + 0.5));
    if (fNew > fCR) NWNX_Creature_SetChallengeRating(oCre, fNew);
}

void main()
{
    object oCre = OBJECT_SELF;
    int bForce = GetLocalInt(oCre, "LOOT_CHAMP_FORCE");
    DeleteLocalInt(oCre, "LOOT_CHAMP_FORCE");
    if (!LootC_IsCandidate(oCre)) return;
    if (!bForce && Random(1000) >= Loot_AreaChampion(GetArea(oCre))) return;
    LootC_Promote(oCre);
}

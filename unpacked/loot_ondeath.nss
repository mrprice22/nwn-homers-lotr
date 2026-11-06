// loot_ondeath - Loot Overhaul Phase 4: rolled drops on a PC-credited kill.
// OBJECT_SELF = the dying creature.  Mirrors loot_model.creature_drop.
//
// Run by bst_ondeath, only on the path where at least one PC contributed (a
// PC's own summon, or a kill with no PC behind it, returns before this), after
// the bestiary has recorded the kill.  bst_ondeath sets LOOT_BENEF (a random
// PC contributor in the corpse's area; unset when none is) on the corpse
// first - it is who Loot_Roll steers by their Phase 6 wishlist.
//
// Never: LOOT_NONE, anything with a master (an enemy summon), an `exclude`d
// creature, or - bosses aside - a creature outside the hostile factions.
// Class: boss (Roll of the Fallen registry) > elite (a champion, elite_include,
// or CR loot level >= area loot level + margin, unless elite_exclude) > normal.
// Level: a boss's levels.json boss_overrides pin, else the creature's CR level
// (a champion's raised CR).  The rolls are delivered to the corpse, droppable,
// so they reach the party roll; they are staggered 0.1s apart so a boss never
// builds 3-4 items in one frame.  All numbers: loot/sources.json "creatures".
//
// Loot Lab: a contributor carrying LOOT_FORCE_DROPS (lootlab_force) forces the
// drop chance to 1000 and gets one "LOOT:" line per kill.
//
// Phase 7 (lo-fate-token): a boss also drops a Shard of Fate at
// LOOTD_FATE_BOSS_CHANCE (forced drops force it), and every PC contributor in
// the corpse's area who carries a Shard and is not locked out on this boss is
// offered a bonus roll (fate_open -> the fate_inc NUI prompt).

#include "loot_inc"
#include "nwnx_creature"

void LootO_Roll(int nLvl, int nFloor, string sProfile, object oBenef, object oDest)
{
    Loot_Roll(nLvl, nFloor, sProfile, oBenef, oDest);
}

void LootO_Named(int nLvl, string sProfile, object oBenef, object oDest)
{
    Loot_GiveNamed(nLvl, LOOT_RARITY_LEGENDARY, sProfile, oBenef, oDest);
}

// The first PC contributor with the Loot Lab "force drops" switch on.
object LootO_Forcer(object oCre)
{
    int nN = GetLocalInt(oCre, "bst_ctrb_n");
    int i;
    for (i = 0; i < nN; i++)
    {
        object m = GetLocalObject(oCre, "bst_ctrb_" + IntToString(i));
        if (GetIsObjectValid(m) && GetIsPC(m) && GetLocalInt(m, "LOOT_FORCE_DROPS"))
            return m;
    }
    return OBJECT_INVALID;
}

void LootO_Shard(object oDest)
{
    Loot_DropShard(oDest);
}

// Offer the Shard of Fate bonus roll to every eligible contributor: a PC, in
// the corpse's area, carrying a Shard, not locked out on this boss.  The
// lockout is re-checked on the Spend click (fate_inc Fate_Spend).
void LootO_FateOffers(object oCre, string sRes, int nLvl)
{
    object oArea = GetArea(oCre);
    string sName = GetName(oCre);
    int nN = GetLocalInt(oCre, "bst_ctrb_n");
    int i;
    for (i = 0; i < nN; i++)
    {
        object m = GetLocalObject(oCre, "bst_ctrb_" + IntToString(i));
        if (!GetIsObjectValid(m) || !GetIsPC(m) || GetIsDM(m)) continue;
        if (GetArea(m) != oArea) continue;
        if (GetLocalObject(m, "FATE_P_CRE") == oCre) continue;   // listed twice
        if (!GetIsObjectValid(Loot_FindShard(m))) continue;
        if (Loot_FateLockedFor(m, sRes, LOOTD_FATE_LOCKOUT) > 0) continue;
        SetLocalObject(m, "FATE_P_CRE", oCre);
        SetLocalString(m, "FATE_P_BOSS", sRes);
        SetLocalString(m, "FATE_P_BNAME", sName);
        SetLocalInt(m, "FATE_P_LVL", nLvl);
        ExecuteScript("fate_open", m);
    }
}

string LootO_ClassName(int nClass)
{
    if (nClass == LOOTD_CLASS_BOSS) return "boss";
    if (nClass == LOOTD_CLASS_ELITE) return "elite";
    return "normal";
}

void main()
{
    object oCre = OBJECT_SELF;
    if (GetLocalInt(oCre, "LOOT_NONE")) return;
    if (GetIsObjectValid(GetMaster(oCre))) return;
    string sRes = GetResRef(oCre);
    if (LootD_CreatureListed(sRes) == LOOTD_LIST_NEVER) return;
    int bBoss = LootD_IsBoss(sRes);
    if (!bBoss && !LootD_IsHostileFaction(NWNX_Creature_GetFaction(oCre))) return;

    int bChamp = GetLocalInt(oCre, "LOOT_CHAMP");
    int nClass = LOOTD_CLASS_NORMAL;
    if (bBoss) nClass = LOOTD_CLASS_BOSS;
    else if (bChamp || Loot_IsNaturalElite(oCre)) nClass = LOOTD_CLASS_ELITE;

    float fCR = GetChallengeRating(oCre);
    int nLvl = bBoss ? LootD_BossLevel(sRes) : 0;
    if (nLvl <= 0) nLvl = LootD_LevelForCR(fCR);

    object oForcer = LootO_Forcer(oCre);
    int nChance = GetIsObjectValid(oForcer) ? 1000 : LootD_CreatureChance(nClass);
    string sProfile = LootD_CreatureProfile(nClass);
    object oBenef = GetLocalObject(oCre, "LOOT_BENEF");

    int nMade = 0;
    if (Random(1000) < nChance)
    {
        int nProfile = LootD_ProfileIndex(sProfile);
        if (nProfile < 0)
        {
            Loot_Warn("creature class " + LootO_ClassName(nClass) + " names unknown profile '"
                      + sProfile + "'");
            return;
        }
        int nRolls = LootD_ProfileRolls(nProfile);
        int nFloor = LootD_ProfileFloor(nProfile);
        if (bBoss && LOOTD_BOSS_EXTRA_CR > 0 && fCR >= IntToFloat(LOOTD_BOSS_EXTRA_CR))
            nRolls++;
        int bNamed = bBoss && Random(1000) < LOOTD_BOSS_NAMED;
        object oMod = GetModule();
        int i;
        for (i = 0; i < nRolls; i++)
            AssignCommand(oMod, DelayCommand(0.1 * IntToFloat(i),
                LootO_Roll(nLvl, nFloor, sProfile, oBenef, oCre)));
        if (bNamed)
            AssignCommand(oMod, DelayCommand(0.1 * IntToFloat(nRolls),
                LootO_Named(nLvl, sProfile, oBenef, oCre)));
        nMade = nRolls + bNamed;
    }

    // Phase 5: a socket gem, rolled independently of the gear chance (a forced
    // drop forces it too), delivered after the gear; a boss's has a tier floor.
    if (GetIsObjectValid(oForcer) || Random(1000) < LootD_CreatureGemChance(nClass))
    {
        AssignCommand(GetModule(), DelayCommand(0.1 * IntToFloat(nMade),
            Loot_DropSocketGem(nLvl, bBoss ? LOOTD_GEM_BOSS_FLOOR : 0, oCre)));
        nMade++;
    }

    // Phase 7: the Shard of Fate - a boss drop, then the bonus-roll offers.
    if (bBoss)
    {
        if (GetIsObjectValid(oForcer) || Random(1000) < LOOTD_FATE_BOSS_CHANCE)
        {
            AssignCommand(GetModule(), DelayCommand(0.1 * IntToFloat(nMade), LootO_Shard(oCre)));
            nMade++;
        }
        LootO_FateOffers(oCre, sRes, nLvl);
    }

    if (GetIsObjectValid(oForcer))
        SendMessageToPC(oForcer, "LOOT: " + GetName(oCre) + " class=" + LootO_ClassName(nClass)
            + (bChamp ? " (champion)" : "") + " cr=" + IntToString(FloatToInt(fCR))
            + " lvl=" + IntToString(nLvl)
            + " area=" + IntToString(Loot_AreaLevel(GetArea(oCre)))
            + " -> " + IntToString(nMade) + " item(s)");
}

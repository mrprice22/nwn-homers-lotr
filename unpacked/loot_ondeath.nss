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

    if (GetIsObjectValid(oForcer))
        SendMessageToPC(oForcer, "LOOT: " + GetName(oCre) + " class=" + LootO_ClassName(nClass)
            + (bChamp ? " (champion)" : "") + " cr=" + IntToString(FloatToInt(fCR))
            + " lvl=" + IntToString(nLvl)
            + " area=" + IntToString(Loot_AreaLevel(GetArea(oCre)))
            + " -> " + IntToString(nMade) + " item(s)");
}

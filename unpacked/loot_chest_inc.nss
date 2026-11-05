// loot_chest_inc.nss - Season 3 rolled loot in chests and containers.
//
// Roadmap: loot-overhaul epic, Phase 3 (rng-based-gear-diablo-world-of-warcraft-style).
// Design: docs.manual/Draft/Loot-Overhaul.html#p3; reference: CLAUDE-loot.md.
//
// Every generic treasure script is a GENERATED one-line wrapper around one of
// the two functions below (loot/sources.json "scripts" -> bin/gen-loot-tables.py
// --apply): the module's respawning chests (chest_respawner, chest_refilllow,
// chest_refillhigh, chestrespawn*) and local overrides of BioWare's stock
// open/bash scripts (nw_o2_class*, nw_o2_general*, x2_02_*, x0_o2_*).  Never
// hand-edit a wrapper; the build gate fails on a stale one.
//
// A container rolls at its AREA's loot level (Loot_ContainerLevel), never the
// opener's, and holds: rolled gear, gold (sometimes paid as treasure gems) and a
// few consumables - see Loot_FillContainer in loot_inc.nss.
//
// Per-placeable locals (set in the toolset):
//   LOOT_LEVEL  int  pin this container's loot level (overrides the area's)
//   LOOT_NONE   int  1 = this container never rolls loot (its script still runs)

#include "loot_inc"

// Who a container is being filled for (Phase 6 wishlist; logged on Epic+ rolls):
// the opener, else the user, else the killer - a henchman or summon resolves to
// its master.
object LootChest_Beneficiary()
{
    object oWho = GetLastOpenedBy();
    if (!GetIsObjectValid(oWho)) oWho = GetLastUsedBy();
    if (!GetIsObjectValid(oWho)) oWho = GetLastKiller();
    object oMaster = GetMaster(oWho);
    while (GetIsObjectValid(oMaster))
    {
        oWho = oMaster;
        oMaster = GetMaster(oWho);
    }
    return oWho;
}

// One fill of OBJECT_SELF with profile sProfile at its loot level.
void LootChest_Fill(string sProfile)
{
    if (GetLocalInt(OBJECT_SELF, "LOOT_NONE")) return;
    Loot_FillContainer(OBJECT_SELF, sProfile, Loot_ContainerLevel(OBJECT_SELF),
                       LootChest_Beneficiary());
}

// The module's respawning chest (OnOpen / OnUsed).  Same timer as the old
// chest_respawner family: the contents are replaced on an open once 200 s of
// the clock below have passed since the last refill, or the clock has wrapped.
void LootChest_Refill(string sProfile)
{
    int nRespawn = 200;
    int nLast = GetLocalInt(OBJECT_SELF, "CS_Opened");
    int nNow = GetTimeSecond() + 60 * GetTimeMinute() + 3600 * GetTimeHour();
    if (nNow > nLast + nRespawn || nLast > nNow)
        SetLocalInt(OBJECT_SELF, "NW_DO_ONCE", 0);
    if (GetLocalInt(OBJECT_SELF, "NW_DO_ONCE") != 0) return;

    object oItem = GetFirstItemInInventory();
    while (GetIsObjectValid(oItem))
    {
        DestroyObject(oItem);
        oItem = GetNextItemInInventory();
    }
    LootChest_Fill(sProfile);
    SetLocalInt(OBJECT_SELF, "CS_Opened", GetTimeSecond() + 60 * GetTimeMinute() + 3600 * GetTimeHour());
    SetLocalInt(OBJECT_SELF, "NW_DO_ONCE", 1);
}

// The stock scripts' ShoutDisturbed (nw_o2_coninclude), without pulling that
// 4,600-line include into every wrapper: creatures of the container's own
// faction within RADIUS_SIZE_LARGE turn on whoever broke or opened it.
void LootChest_ShoutDisturbed()
{
    object oCulprit = GetIsDead(OBJECT_SELF) ? GetLastAttacker() : GetLastOpenedBy();
    if (!GetIsObjectValid(oCulprit)) return;
    location lHere = GetLocation(OBJECT_SELF);
    object oTarget = GetFirstObjectInShape(SHAPE_SPHERE, RADIUS_SIZE_LARGE, lHere, TRUE, OBJECT_TYPE_CREATURE);
    while (GetIsObjectValid(oTarget))
    {
        if (GetFactionEqual(oTarget, OBJECT_SELF))
        {
            SetIsTemporaryEnemy(oCulprit, oTarget);
            AssignCommand(oTarget, ActionAttack(oCulprit));
        }
        oTarget = GetNextObjectInShape(SHAPE_SPHERE, RADIUS_SIZE_LARGE, lHere, TRUE, OBJECT_TYPE_CREATURE);
    }
}

// BioWare's stock treasure behaviour (OnOpen and OnDeath of a bashable
// placeable): filled once in the placeable's life, then shout "disturbed" so
// nearby creatures react, as the stock scripts do.
void LootChest_Once(string sProfile)
{
    if (GetLocalInt(OBJECT_SELF, "NW_DO_ONCE") != 0) return;
    LootChest_Fill(sProfile);
    SetLocalInt(OBJECT_SELF, "NW_DO_ONCE", 1);
    LootChest_ShoutDisturbed();
}

// cleanup  --  Area OnExit: once the last PC leaves, clear encounter creatures
// and dropped loot.
//
// Bosses (CR > 60, the same rule bin/gen-boss-registry.py uses) are NOT
// destroyed: a solo player who dies to one respawns elsewhere, which is an
// area exit, and deleting the boss there made it vanish mid-fight (roadmap
// kerfualls-disappearing-act). Instead the boss is left standing for
// CLN_BOSS_GRACE seconds so the player can run back to a still-wounded boss;
// if the area is still empty when that expires, the boss is reset in place --
// healed, rested, cleared of foreign effects and returned to its spawn point.

const float CLN_BOSS_GRACE = 900.0;

int CLN_IsBoss(object oCre)
{
    return GetChallengeRating(oCre) > 60.0;
}

int CLN_AreaHasPC(object oArea)
{
    object oPC = GetFirstPC();
    while (GetIsObjectValid(oPC))
    {
        if (GetArea(oPC) == oArea)
            return TRUE;
        oPC = GetNextPC();
    }
    return FALSE;
}

void CLN_ResetBoss(object oBoss)
{
    // Strip what players put on it; keep what it applied to itself
    // (nw_c2_default9 gives some creatures permanent spawn effects).
    effect e = GetFirstEffect(oBoss);
    while (GetIsEffectValid(e))
    {
        if (GetEffectCreator(e) != oBoss)
            RemoveEffect(oBoss, e);
        e = GetNextEffect(oBoss);
    }

    AssignCommand(oBoss, ClearAllActions(TRUE));
    ForceRest(oBoss);
    ApplyEffectToObject(DURATION_TYPE_INSTANT,
        EffectHeal(GetMaxHitPoints(oBoss)), oBoss);

    location lHome = GetLocalLocation(oBoss, "spawn");
    if (GetIsObjectValid(GetAreaFromLocation(lHome)))
        AssignCommand(oBoss, JumpToLocation(lHome));
}

void CLN_BossGraceExpired(object oArea, int nGen)
{
    // A later empty-out re-armed the grace; that newer timer owns the reset.
    if (GetLocalInt(oArea, "cln_boss_gen") != nGen || CLN_AreaHasPC(oArea))
        return;

    object oCre = GetFirstObjectInArea(oArea);
    while (GetIsObjectValid(oCre))
    {
        if (GetIsEncounterCreature(oCre) && CLN_IsBoss(oCre) && !GetIsDead(oCre))
            CLN_ResetBoss(oCre);
        oCre = GetNextObjectInArea(oArea);
    }
}

void TrashObject(object oObject)
{
    if (GetObjectType(oObject) == OBJECT_TYPE_PLACEABLE) {
        object oItem = GetFirstItemInInventory(oObject);
        while (GetIsObjectValid(oItem))
        {
            TrashObject(oItem);
           oItem = GetNextItemInInventory(oObject);
        }
    }
    DestroyObject(oObject);
}
void main()
{
    if(!GetIsPC(GetExitingObject()) ) {
        return; }
    if (CLN_AreaHasPC(OBJECT_SELF))
        return;

    int bBoss = FALSE;
    object oObject = GetFirstObjectInArea(OBJECT_SELF);
    while (oObject != OBJECT_INVALID)
    {
        if (GetIsEncounterCreature(oObject))
        {
            if (CLN_IsBoss(oObject))
                bBoss = TRUE;
            else
                DestroyObject(oObject);
        }
        oObject = GetNextObjectInArea(OBJECT_SELF);
    }
    if (bBoss)
    {
        int nGen = GetLocalInt(OBJECT_SELF, "cln_boss_gen") + 1;
        SetLocalInt(OBJECT_SELF, "cln_boss_gen", nGen);
        DelayCommand(CLN_BOSS_GRACE, CLN_BossGraceExpired(OBJECT_SELF, nGen));
    }

    object oItem = GetFirstObjectInArea();
    while (GetIsObjectValid(oItem))
    {
       int iObjectType = GetObjectType(oItem);
        switch (iObjectType) {
        case OBJECT_TYPE_PLACEABLE:
     if (GetTag(oItem) != "BodyBag") {
                break; }
        case OBJECT_TYPE_ITEM:
        TrashObject(oItem); }
        oItem = GetNextObjectInArea();
}
}

// Weather Top's Hidden Court -- the garrison gives chase (roadmap: wtop-court-pursuit)
//
// area028 is ONE area. What reads in game as an upper terrace, a long middle
// level and the royal floor below is tdr01 tileset elevation, not separate
// areas -- so a player who simply runs can cross the whole court and arrive at
// the thrones with all 51 of the garrison still standing at their posts behind
// them, leaving the King and Queen to fight alone. Stock BioWare AI is what
// allows it: x2_def_percept drops a target the moment it can no longer see it,
// and the creature settles back where it stands.
//
// This is the fix the admin asked for: every court NPC that has SEEN the player
// follows them down, at its own running speed and on its own feet -- never a
// teleport -- unless it has a combatant of its own to deal with.
//
// WHY A SINGLE AREA LOOP AND NOT 51 HEARTBEATS. An OnHeartbeat wrapper on the
// three court blueprints would put this work on 51 separate objects every six
// seconds. One self-scheduling loop on the area does the same job in one script
// invocation per tick, and it only runs at all while a player is actually in
// the court. That matters here: this box runs the live season, the dev realm
// and its own builds on four cores, and NWN's main loop is single-threaded, so
// a scheduling cost IS the lag players report (see CLAUDE.md, "Resource
// priority").
//
// The King and Queen are excluded by construction -- their tags are simply not
// in the garrison list. They hold the thrones; that is the whole point of the
// run. wtop_royal.nss additionally assumes the pair are in the throne area
// together, so dragging them around would weaken their own bond script.
//
// Nothing here can trip leash_to_area: every target is a PC in THIS area, so a
// chaser never follows anyone out through wtopcourt2wtop into area026.
//
// Armed from wtop_c_enter.nss (area028 OnEnter) on the first PC entry.

// ---- on the area -----------------------------------------------------------
const string WTOP_CH_LOOP = "WTOP_CHASE_LOOP";   // re-arm guard: one loop only

// ---- on each garrison creature ---------------------------------------------
const string WTOP_CH_ON   = "WTOP_CHASE";        // latched "I have seen a player"
const string WTOP_CH_TGT  = "WTOP_CHASE_TGT";    // who it is after

const float  WTOP_CH_TICK  =  6.0;   // one pass per combat round
const float  WTOP_CH_BUSY  = 12.0;   // a visible enemy this close == already busy
const float  WTOP_CH_CLOSE =  3.0;   // stop distance handed to the move action

// The three tags wtop_court.nss fills. Royals are deliberately absent.
const string WTOP_CH_T1 = "WeathertopRoyalGuard";
const string WTOP_CH_T2 = "WeathertopRoyalArcher";
const string WTOP_CH_T3 = "WeathertopRoyalMagus";

// Player list for this tick, stashed on the area so the per-creature pass does
// not walk GetFirstPC/GetNextPC 51 times over.
const string WTOP_CH_NPC = "WTOP_CHASE_NPC";
const string WTOP_CH_PC  = "WTOP_CHASE_PC";      // + index

// Collect the live, non-DM players standing in this area. Returns how many.
int WtopChaseGatherPCs(object oArea)
{
    int nCount = 0;
    object oPC = GetFirstPC();

    while (GetIsObjectValid(oPC))
    {
        if (GetArea(oPC) == oArea && !GetIsDM(oPC) && !GetIsDead(oPC))
            SetLocalObject(oArea, WTOP_CH_PC + IntToString(nCount++), oPC);

        oPC = GetNextPC();
    }

    SetLocalInt(oArea, WTOP_CH_NPC, nCount);
    return nCount;
}

void WtopChaseClearPCs(object oArea)
{
    int i, n = GetLocalInt(oArea, WTOP_CH_NPC);
    for (i = 0; i < n; i++)
        DeleteLocalObject(oArea, WTOP_CH_PC + IntToString(i));
    DeleteLocalInt(oArea, WTOP_CH_NPC);
}

// The player this creature should be running at: the one it has its teeth in if
// that is still valid, otherwise the nearest one it can reach.
object WtopChasePick(object oArea, object oCre)
{
    object oOld = GetLocalObject(oCre, WTOP_CH_TGT);
    if (GetIsObjectValid(oOld) && !GetIsDead(oOld) && GetArea(oOld) == oArea)
        return oOld;

    object oBest = OBJECT_INVALID;
    float fBest  = 0.0;
    int i, n = GetLocalInt(oArea, WTOP_CH_NPC);

    for (i = 0; i < n; i++)
    {
        object oPC = GetLocalObject(oArea, WTOP_CH_PC + IntToString(i));
        if (!GetIsObjectValid(oPC)) continue;

        float f = GetDistanceBetween(oCre, oPC);
        if (!GetIsObjectValid(oBest) || f < fBest)
        {
            oBest = oPC;
            fBest = f;
        }
    }
    return oBest;
}

// Send one garrison member back to the post wtop_court.nss spawned it on.
// Walking, not running -- the fight is over, and a court that jogs back into
// formation looks wrong.
void WtopChaseGoHome(object oCre)
{
    if (!GetLocalInt(oCre, WTOP_CH_ON)) return;

    DeleteLocalInt(oCre, WTOP_CH_ON);
    DeleteLocalObject(oCre, WTOP_CH_TGT);

    if (GetIsDead(oCre)) return;

    // "spawn" is pinned by wtop_court.nss and is the same local leash_to_area
    // and se_respawn_inc read.
    location lHome = GetLocalLocation(oCre, "spawn");
    if (!GetIsObjectValid(GetAreaFromLocation(lHome))) return;

    AssignCommand(oCre, ClearAllActions());
    AssignCommand(oCre, ActionForceMoveToLocation(lHome, FALSE));
}

void WtopChaseOne(object oArea, object oCre)
{
    if (GetIsDead(oCre)) return;

    // LATCH. GetObjectSeen is the engine's own record of who has line of sight
    // on whom, so no perception wrapper is needed on the three blueprints. Once
    // set the latch stays set: the player breaking line of sight by running is
    // exactly the case this feature exists for.
    if (!GetLocalInt(oCre, WTOP_CH_ON))
    {
        int i, n = GetLocalInt(oArea, WTOP_CH_NPC);
        for (i = 0; i < n; i++)
        {
            object oPC = GetLocalObject(oArea, WTOP_CH_PC + IntToString(i));
            if (GetIsObjectValid(oPC) && GetObjectSeen(oPC, oCre))
            {
                SetLocalInt(oCre, WTOP_CH_ON, TRUE);
                SetLocalObject(oCre, WTOP_CH_TGT, oPC);
                break;
            }
        }
        if (!GetLocalInt(oCre, WTOP_CH_ON)) return;
    }

    // BUSY. "if there are no other combatants for them" -- somebody is already
    // in this one's face, so leave it and the stock AI entirely alone.
    object oNear = GetNearestCreature(CREATURE_TYPE_REPUTATION, REPUTATION_TYPE_ENEMY,
                                      oCre, 1, CREATURE_TYPE_PERCEPTION, PERCEPTION_SEEN);
    if (GetIsObjectValid(oNear) && GetDistanceBetween(oCre, oNear) <= WTOP_CH_BUSY)
        return;

    object oTarget = WtopChasePick(oArea, oCre);
    if (!GetIsObjectValid(oTarget)) return;

    if (GetDistanceBetween(oCre, oTarget) <= WTOP_CH_CLOSE) return;

    // Only re-issue when the order would actually change something. Without
    // this test the six-second tick would ClearAllActions() a creature that is
    // already mid-run and stutter the whole pursuit.
    if (oTarget == GetLocalObject(oCre, WTOP_CH_TGT)
        && GetCurrentAction(oCre) == ACTION_MOVETOPOINT)
        return;

    SetLocalObject(oCre, WTOP_CH_TGT, oTarget);
    AssignCommand(oCre, ClearAllActions());
    AssignCommand(oCre, ActionForceMoveToObject(oTarget, TRUE, WTOP_CH_CLOSE));
}

// GetObjectByTag only ever returns the first match, so walk the nth-object form
// -- the same idiom wtop_court.nss uses to fill the posts.
void WtopChaseSweep(object oArea, string sTag, int bAnyPCs)
{
    int n = 0;
    object oCre = GetObjectByTag(sTag, n);

    while (GetIsObjectValid(oCre))
    {
        if (GetArea(oCre) == oArea)
        {
            if (bAnyPCs) WtopChaseOne(oArea, oCre);
            else         WtopChaseGoHome(oCre);
        }
        oCre = GetObjectByTag(sTag, ++n);
    }
}

void main()
{
    object oArea = OBJECT_SELF;

    int bAnyPCs = WtopChaseGatherPCs(oArea) > 0;

    WtopChaseSweep(oArea, WTOP_CH_T1, bAnyPCs);
    WtopChaseSweep(oArea, WTOP_CH_T2, bAnyPCs);
    WtopChaseSweep(oArea, WTOP_CH_T3, bAnyPCs);

    WtopChaseClearPCs(oArea);

    if (!bAnyPCs)
    {
        // Court empty: everyone has been sent back to their post and the loop
        // stands down. wtop_c_enter.nss re-arms it on the next player entry.
        DeleteLocalInt(oArea, WTOP_CH_LOOP);
        return;
    }

    DelayCommand(WTOP_CH_TICK, ExecuteScript("wtop_chase", oArea));
}

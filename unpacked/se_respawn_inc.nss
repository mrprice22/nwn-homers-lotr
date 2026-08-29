//::///////////////////////////////////////////////
//:: Sir Elric's Simple Creature Respawns - SE v1.5
//:: FileName - se_respawn_inc
//::///////////////////////////////////////////////
//:: Place any creatures from the stock or custom palette in your world.
//:: They will respawn in that exact location & wander around the area.
//:: Respawn timers are tuned in boss_tune.nss (CRE_RESPAWN_SECONDS for
//:: ordinary creatures, BOSS_RESPAWN_SECONDS for Roll-of-the-Fallen bosses)
//:: Your all done, simple.
//::///////////////////////////////////////////////
//:: Tagged creatures with _NSP will not respawn eg. NW_GOBLINA_NSP
//:: Encounter creatures will not respawn - SE v1.4
//:://////////////////////////////////////////////
//:: Created By: Sir Elric
//:: Created On: 17th February, 2004 SE v1.1
//:: Updated On: 8th March, 2004 SE v1.5
//:://////////////////////////////////////////////

//::///////////////////////////////////////////////
//:: INSTRUCTIONS FOR FUTURE BW PATCH RELEASES ie: 1.62 and beyond.
//::///////////////////////////////////////////////
/* After a BW patch should the default nw_c2_ scripts need updating,
   to add system back in simple as 1,2,3.

Delete the old - NW_C2_DEFAULT7, NW_C2_DEFAULT9, NW_C2_HERBIVORE, & NW_C2_OMNIVORE then open the new scripts.

1. Add this include file(approx at line 17) to NW_C2_DEFAULT7
   ie. #include "se_respawn_inc"

2. Add these lines(approx at line 44) to NW_C2_DEFAULT7 -
     // Do not respawn creature if tagged with _NSP eg. NW_GOBLINA_NSP
    if (FindSubString(GetTag(OBJECT_SELF), "NSP") > -1)
    return;
    { SE_DoCreatureRespawn(); }

3. Add this line(approx at line 298,74 & 74 respectively) to NW_C2_DEFAULT9, NW_C2_HERBIVORE, & NW_C2_OMNIVORE -
   SetLocalLocation(OBJECT_SELF, "spawn", GetLocation(OBJECT_SELF));

3a.   *** Optional ***
   To set creatures to wander, open NW_C2_DEFAULT9, uncomment:
   Line 119 - SetSpawnInCondition(NW_FLAG_AMBIENT_ANIMATIONS);
   Line 148 - SetAnimationCondition(NW_ANIM_FLAG_CONSTANT);

*/


#include "boss_tune"

// How long this creature stays dead. Roll-of-the-Fallen bosses respawn on the
// boss timer, everything else on the world timer - both tuned in boss_tune.nss,
// never here. One indexed SELECT against respawndb per death (the same campaign
// DB the board and the enrage system already read); if the table is not seeded
// yet the query simply misses and the creature takes the world timer.
float SE_RespawnDelay(object oCre)
{
    sqlquery q = SqlPrepareQueryCampaign("respawndb",
        "SELECT 1 FROM boss_registry WHERE resref=@r" +
        " UNION SELECT 1 FROM boss_alias WHERE resref=@r");
    SqlBindString(q, "@r", GetStringLowerCase(GetResRef(oCre)));
    if (SqlStep(q)) return IntToFloat(BOSS_RESPAWN_SECONDS);
    return IntToFloat(CRE_RESPAWN_SECONDS);
}

void SE_RespawnObject(int nType, string sResRef, location lLoc, string sNewTag)
{
  CreateObject(nType, sResRef, lLoc, FALSE, sNewTag);
}



void SE_DoCreatureRespawn()
{
  location lLoc;
  float fFacing;
  int iEncounter = GetIsEncounterCreature(OBJECT_SELF);
  if(iEncounter)//Encounter creatures will not respawn - SE v1.4
  return;
  int nType = GetObjectType(OBJECT_SELF);
  string sRef = GetResRef(OBJECT_SELF);
  string sTag = GetTag(OBJECT_SELF);

        lLoc = GetLocalLocation(OBJECT_SELF, "spawn");
        if (GetIsObjectValid(GetAreaFromLocation(lLoc)))
          { DeleteLocalInt(OBJECT_SELF, "spawn"); }
        else
          { lLoc = GetLocation(OBJECT_SELF); }
        fFacing = GetFacing(OBJECT_SELF);
// *** RESPAWN TIMER: tuned in boss_tune.nss, not here ***//
  float fDelay = SE_RespawnDelay(OBJECT_SELF);
  AssignCommand(GetModule(), DelayCommand(fDelay, SE_RespawnObject(nType, sRef, lLoc, sTag)));
}

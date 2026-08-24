//::///////////////////////////////////////////////
//:: Mod_OnSpawnBtnDn -- the player clicked Respawn.
//::
//:: The respawn itself lives in respawn_inc::LOTR_RespawnPC(), moved there by
//:: roadmap petrification-respawn-defect-round-4 so the petrification timeout
//:: can respawn a player who has no working button to click. Behaviour here is
//:: unchanged: same bind point, same penalty, same amulet cleanup.
//:://////////////////////////////////////////////

#include "respawn_inc"

void main ()
{
    LOTR_RespawnPC(GetLastRespawnButtonPresser());
}

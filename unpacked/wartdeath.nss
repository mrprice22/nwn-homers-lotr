// wartdeath.nss — OnDeath for the Wart Gondorian Gate Captain (gondorianguar005).
//
// Runs the shared HotU XP-fix handler (hotuxpfix) that this boss used to have,
// then respawns the boss 15 min after death so it appears with an accurate
// countdown on the Roll of the Fallen board. hotuxpfix is left unchanged so the
// non-boss Black Numenorean mobs that also use it keep their old behaviour.
#include "se_respawn_inc"

void main()
{
    ExecuteScript("hotuxpfix", OBJECT_SELF);
    if (FindSubString(GetTag(OBJECT_SELF), "NSP") == -1)
        SE_DoCreatureRespawn();
}

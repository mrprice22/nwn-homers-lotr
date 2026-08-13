//::///////////////////////////////////////////////
//:: sp_devgate - StartingConditional for dev-only conversations
//::
//:: Returns SP_DEV_TOOLS, so a dialogue carrying dev tools offers nothing at
//:: all in an environment where those tools are off (see bin/season-profile.py).
//::
//:: WHY THIS EXISTS, and why the module-load purge was not enough:
//:: onmoduleload destroys the Ping Pong NPC (tag BUTCHA) when SP_DEV_TOOLS is
//:: off. That silently did nothing on the live season 2 launch, because the
//:: creature is flagged Plot + Immortal and DestroyObject() refuses a plot
//:: creature. The NPC survived into production with ~70 cheat scripts behind
//:: it - set level 1-40, hand out gold, destroy equipment, heal - of which only
//:: the 41-60 tier was independently guarded.
//::
//:: Gating the CONVERSATION is the robust half: it is one edit that covers
//:: every node and every script behind it, and it holds even if the creature
//:: is spawned by a DM, restored from a save, or survives the purge again.
//:: Keep both - the purge removes the NPC, this makes it inert if it is there.
//:://////////////////////////////////////////////
#include "season_prof_inc"

int StartingConditional()
{
    return SP_DEV_TOOLS;
}

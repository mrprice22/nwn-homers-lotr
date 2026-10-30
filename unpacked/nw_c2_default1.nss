//::///////////////////////////////////////////////
//:: Default On Heartbeat
//:: NW_C2_DEFAULT1
//:: Copyright (c) 2001 Bioware Corp.
//:://////////////////////////////////////////////
/*
    This script will have people perform default
    animations.
*/
//:://////////////////////////////////////////////
//:: Created By: Preston Watamaniuk
//:: Created On: Nov 23, 2001
//:://////////////////////////////////////////////
// Deliberately empty. It used to fake-cast Death Ward at GetObjectByTag("spells"),
// a tag no object carries: a failed lookup and an action-queue push on every
// creature using this heartbeat, every 6 seconds, for no effect (roadmap:
// perf-nw-c2-default1-noop). The NW_I0_GENERIC include went with it.

void main()
{
}

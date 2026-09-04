// The sealed door of the hidden court (roadmap: forbidden-realms-key-tier)
//
// OnOpen for the area028 door tagged wtop_4key_door. The admin's spec, written
// on the door itself in the toolset:
//
//   "Needs all 4 wtop key fragments to open.
//    Key is consumed on open
//    Stays open for 10 seconds, making creeking/mechanical noises and jittering
//    every 2 second
//    After 10 second total door closes shut and relocks itself - players need
//    to teleport to get out"
//
// The first two lines are DATA, not code, and are already set on the door
// instance: KeyName "wtop_4key_whole" (the tag of the assembled key made at the
// lever outside), KeyRequired so the lock cannot simply be picked past, and
// AutoRemoveKey so the engine eats the key in the turning. This script is the
// third and fourth lines.
//
// The relock is why the court is a committed trip: once the party is through,
// the only ways out are the ordinary transition on the antechamber side of this
// door -- which is now shut -- or a teleport. That is deliberate and is the
// admin's call, not an oversight.

const float WTOP_DOOR_OPEN_FOR = 10.0;
const float WTOP_DOOR_TICK     = 2.0;

// One strain of the mechanism: the locked-door rattle plus a puff of dust off
// the lintel. Stock sound resrefs, verified against the game's own key file.
void WtopDoorStrain(object oDoor)
{
    if (!GetIsObjectValid(oDoor)) return;
    if (!GetIsOpen(oDoor)) return;          // already slammed; stop rattling

    AssignCommand(oDoor, PlaySound("as_dr_locked2"));
    ApplyEffectAtLocation(DURATION_TYPE_INSTANT,
                          EffectVisualEffect(VFX_IMP_DUST_EXPLOSION),
                          GetLocation(oDoor));
}

void WtopDoorSlam(object oDoor)
{
    if (!GetIsObjectValid(oDoor)) return;

    AssignCommand(oDoor, PlaySound("as_dr_stonlgcl1"));
    AssignCommand(oDoor, ActionCloseDoor(oDoor));
    DelayCommand(1.0, SetLocked(oDoor, TRUE));
}

void main()
{
    object oDoor = OBJECT_SELF;

    AssignCommand(oDoor, PlaySound("as_dr_stonlgop1"));

    float f;
    for (f = WTOP_DOOR_TICK; f < WTOP_DOOR_OPEN_FOR; f += WTOP_DOOR_TICK)
        DelayCommand(f, WtopDoorStrain(oDoor));

    DelayCommand(WTOP_DOOR_OPEN_FOR, WtopDoorSlam(oDoor));
}

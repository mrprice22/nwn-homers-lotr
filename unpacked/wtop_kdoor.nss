// The sealed door of the hidden court (roadmap: forbidden-realms-key-tier)
//
// OnOpen for BOTH halves of the sealed crossing in area028: the outer door
// tagged wtop_4key_door and the inner one tagged wtop_4key_door_in (the old
// CryptExit doorway, six metres east). They are LinkedTo each other, so the
// pair is one two-way area transition.
//
// The admin's spec, written on the outer door itself in the toolset:
//
//   "Needs all 4 wtop key fragments to open.
//    Key is consumed on open
//    Stays open for 10 seconds, making creeking/mechanical noises and jittering
//    every 2 second
//    After 10 second total door closes shut and relocks itself - players need
//    to teleport to get out"
//
// The first two lines are DATA, not code, and are set on both door instances:
// KeyName "wtop_4key_whole" (the tag of the assembled key made at the lever
// outside), KeyRequired so the lock cannot simply be picked past, and
// AutoRemoveKey so the engine eats the key in the turning. This script is the
// third and fourth lines, plus the lockstep.
//
// Lockstep: whichever half a player unlocks, this script swings the OTHER half
// open at the same moment and slams both shut together ten seconds later. The
// partner is opened by script, so the engine never asks it for a key -- one key
// buys exactly one crossing, in whichever direction it was spent.
//
// So the court is still a committed trip, but there are three ways back out
// rather than one: the portal behind the thrones, a second key, or someone on
// the entrance side turning their own key to let you through.

const string WTOP_DOOR_OUT = "wtop_4key_door";
const string WTOP_DOOR_IN  = "wtop_4key_door_in";

const float WTOP_DOOR_OPEN_FOR = 10.0;
const float WTOP_DOOR_TICK     = 2.0;

// Set on the partner just before it is opened by script. Its own OnOpen -- this
// same file -- sees the flag, clears it and returns, so the two doors do not
// open each other in an endless round.
const string WTOP_LOCKSTEP = "WTOP_LOCKSTEP";

// The other half of the pair, or OBJECT_INVALID. Both doors stand in area028,
// so nearest-by-tag resolves them; GetObjectByTag is the fallback for the case
// where OBJECT_SELF is somehow not the one we think it is.
object WtopPartnerDoor(object oDoor)
{
    string sOther = (GetTag(oDoor) == WTOP_DOOR_IN) ? WTOP_DOOR_OUT : WTOP_DOOR_IN;

    object oPartner = GetNearestObjectByTag(sOther, oDoor);
    if (!GetIsObjectValid(oPartner)) oPartner = GetObjectByTag(sOther);
    return oPartner;
}

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

    // Opened by the other half's lockstep, not by a player's key: that half has
    // already scheduled the strain ticks and the slam for both of us.
    if (GetLocalInt(oDoor, WTOP_LOCKSTEP))
    {
        DeleteLocalInt(oDoor, WTOP_LOCKSTEP);
        return;
    }

    object oPartner = WtopPartnerDoor(oDoor);

    AssignCommand(oDoor, PlaySound("as_dr_stonlgop1"));

    if (GetIsObjectValid(oPartner) && !GetIsOpen(oPartner))
    {
        SetLocalInt(oPartner, WTOP_LOCKSTEP, TRUE);
        SetLocked(oPartner, FALSE);
        AssignCommand(oPartner, ActionOpenDoor(oPartner));
    }

    float f;
    for (f = WTOP_DOOR_TICK; f < WTOP_DOOR_OPEN_FOR; f += WTOP_DOOR_TICK)
    {
        DelayCommand(f, WtopDoorStrain(oDoor));
        DelayCommand(f, WtopDoorStrain(oPartner));
    }

    DelayCommand(WTOP_DOOR_OPEN_FOR, WtopDoorSlam(oDoor));
    DelayCommand(WTOP_DOOR_OPEN_FOR, WtopDoorSlam(oPartner));
}

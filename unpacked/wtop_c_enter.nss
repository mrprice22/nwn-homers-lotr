// Weather Top's Hidden Court (roadmap: forbidden-realms-key-tier)
// area028 OnEnter wrapper: the standard anti-kiting leash, then make sure the
// court garrison is standing at its posts. Same wrapper pattern as
// wtop_enter.nss on the hill above.
//
// area028 shipped from the toolset with an EMPTY OnEnter, so before this there
// was no leash on the court at all -- a party could have pulled the King down
// the stairs and out through the transition.
//
// It also arms wtop_chase.nss, the garrison pursuit loop, which is what stops a
// player simply running the length of the court past 51 guards.
void main()
{
    ExecuteScript("leash_to_area", OBJECT_SELF);

    if (!GetIsPC(GetEnteringObject())) return;

    ExecuteScript("wtop_court", OBJECT_SELF);

    // Arm the pursuit loop once. It stands itself down when the court empties
    // and deletes this flag, so the next player in re-arms it. The guard is
    // what stops a second arrival from starting a second loop on the same area.
    if (!GetLocalInt(OBJECT_SELF, "WTOP_CHASE_LOOP"))
    {
        SetLocalInt(OBJECT_SELF, "WTOP_CHASE_LOOP", TRUE);
        ExecuteScript("wtop_chase", OBJECT_SELF);
    }
}

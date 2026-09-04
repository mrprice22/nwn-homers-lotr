// Weather Top's Hidden Court (roadmap: forbidden-realms-key-tier)
// area028 OnEnter wrapper: the standard anti-kiting leash, then make sure the
// court garrison is standing at its posts. Same wrapper pattern as
// wtop_enter.nss on the hill above.
//
// area028 shipped from the toolset with an EMPTY OnEnter, so before this there
// was no leash on the court at all -- a party could have pulled the King down
// the stairs and out through the transition.
void main()
{
    ExecuteScript("leash_to_area", OBJECT_SELF);

    if (GetIsPC(GetEnteringObject()))
        ExecuteScript("wtop_court", OBJECT_SELF);
}

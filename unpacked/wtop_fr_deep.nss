// Forbidden Realms: Enter -- the sealed end (roadmap: forbidden-realms-key-tier)
//
// OnEnter of the ForbidRealms_TBD trigger in area027, at (23.34, 39.04): the
// deepest point of the room, among the green and cyan sparks, past
// ForbiddenRealmsDoor.
//
// Message only, foreshadowing the royal court that is not built yet (it will
// hang off wtop_hiddencave in area026). The trigger keeps its placeholder tag
// until that area exists -- renaming it is toolset work.
//
// Once per character. See wtop_fr_welcome.nss for the idiom.

const string WTOP_FR_SEEN = "WTOP_FR_DEEP";

void main()
{
    object oPC = GetEnteringObject();
    if (!GetIsPC(oPC)) return;
    if (GetLocalInt(oPC, WTOP_FR_SEEN)) return;
    SetLocalInt(oPC, WTOP_FR_SEEN, TRUE);

    FloatingTextStringOnCreature(
        "The passage ends in worked stone that was never meant to be a wall. "
        + "It was raised in haste, and it was raised from the other side. "
        + "Whatever the court of Amon Sul shut in down here, no one has ever "
        + "let it out.", oPC, FALSE);
}

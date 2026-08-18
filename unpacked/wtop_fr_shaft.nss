// Forbidden Realms: Enter -- the light shaft (roadmap: forbidden-realms-key-tier)
//
// OnEnter of the ForbidRealmsLghtShaft trigger in area027, at (8.73, 28.06),
// beside the x3_plc_ylights placeable at (9.7, 30.0). This is past
// ForbiddenRealmsDoor, so only a party that got the door open ever sees it.
//
// Once per character, message only. See wtop_fr_welcome.nss for the idiom.

const string WTOP_FR_SEEN = "WTOP_FR_SHAFT";

void main()
{
    object oPC = GetEnteringObject();
    if (!GetIsPC(oPC)) return;
    if (GetLocalInt(oPC, WTOP_FR_SEEN)) return;
    SetLocalInt(oPC, WTOP_FR_SEEN, TRUE);

    FloatingTextStringOnCreature(
        "A shaft of pale light falls here out of stone that has no opening "
        + "above it. It does not warm you. Where it touches the floor the dust "
        + "has never settled - as though something passes through it, and "
        + "passes often.", oPC, FALSE);
}

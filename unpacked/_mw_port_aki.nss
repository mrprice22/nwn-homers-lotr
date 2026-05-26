void main()
{
    object oPC = GetLastSpeaker();

    if (GetLocalInt(GetModule(), "MW_HALL_OCCUPIED"))
    {
        FloatingTextStringOnCreature(
            "The Hall of Legends is occupied. Return when the seeker within has departed.",
            oPC, FALSE);
        return;
    }

    SetLocalInt(GetModule(), "MW_HALL_OCCUPIED", 1);
    AssignCommand(oPC, JumpToLocation(GetLocation(GetWaypointByTag("MW_SPAWN_AKIRA"))));
}

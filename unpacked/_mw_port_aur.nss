void main()
{
    object oPC = GetLastSpeaker();
    AssignCommand(oPC, JumpToLocation(GetLocation(GetWaypointByTag("MW_SPAWN_AURELIUS"))));
}

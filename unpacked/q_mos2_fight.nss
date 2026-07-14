// The Miller's Other Son -- the Voice of the Red Eye turns on the player
// (Persuade failed, or the player chose steel). Stage 2 (outcome "fought")
// is stamped by q_mos2_death when he actually falls.
void main()
{
    object oPC = GetPCSpeaker();
    ChangeToStandardFaction(OBJECT_SELF, STANDARD_FACTION_HOSTILE);
    ActionAttack(oPC);
}

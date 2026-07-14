// Ferny's Return -- the player refuses the bribe and calls the impostor out.
// He turns on them; stage 2 (outcome "fought") is stamped by q_fret_death
// when he actually falls.
void main()
{
    object oPC = GetPCSpeaker();
    ChangeToStandardFaction(OBJECT_SELF, STANDARD_FACTION_HOSTILE);
    ActionAttack(oPC);
}

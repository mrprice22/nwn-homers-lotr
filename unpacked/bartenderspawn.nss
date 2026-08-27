//Sets the phrase to look for, and starts bartender listening
void main()
{
    // Record the spawn home: se_respawn_inc respawns here rather than where
    // the corpse fell, and leash_to_area.nss leashes to this area.
    SetLocalLocation(OBJECT_SELF, "spawn", GetLocation(OBJECT_SELF));
    SetListenPattern(OBJECT_SELF, "**please**", 69);
    SetListening(OBJECT_SELF, TRUE);
}

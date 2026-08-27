// * creature randomly walks around
// * cannot be interacted with

void main()
{
    // Record the spawn home: se_respawn_inc respawns here rather than where
    // the corpse fell, and leash_to_area.nss leashes to this area.
    SetLocalLocation(OBJECT_SELF, "spawn", GetLocation(OBJECT_SELF));
    if (IsInConversation(OBJECT_SELF) == FALSE)
    {
        ClearAllActions();
        ActionRandomWalk();
    }
}

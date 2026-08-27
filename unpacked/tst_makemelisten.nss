void main()
{

    // Record the spawn home: se_respawn_inc respawns here rather than where
    // the corpse fell, and leash_to_area.nss leashes to this area.
    SetLocalLocation(OBJECT_SELF, "spawn", GetLocation(OBJECT_SELF));
SetListening( OBJECT_SELF, TRUE);
SetListenPattern( OBJECT_SELF, "**",101);


//Fix it so he can hear invisible characters
ApplyEffectToObject(DURATION_TYPE_PERMANENT, EffectUltravision(), OBJECT_SELF, 99999.9);
ApplyEffectToObject(DURATION_TYPE_PERMANENT, EffectTrueSeeing(), OBJECT_SELF, 99999.9);

}

//::///////////////////////////////////////////////
//:: fb_smith_spawn -- OnSpawn for Kalrun the Deathless (kallristsmith).
//::
//:: Runs the stock nw_c2_default9 behaviour, then pairs the smith with the
//:: Kallrist Crypt guardian so the Fell Beast stops duelling him.
//::
//:: The pairing is applied from BOTH sides because either can spawn first: the
//:: guardian does it in spawn_fellbeast.nss, and this covers the case where the
//:: beast is already standing there when the smith loads (or respawns onto him
//:: 15 minutes after a kill -- see se_respawn_inc.nss).
//::
//:: Roadmap: the-fell-beast-attacks.
//:://////////////////////////////////////////////

void main()
{
    // Stock generic-NPC spawn behaviour first -- ExecuteScript preserves
    // OBJECT_SELF, so nw_c2_default9 sets up this creature exactly as before.
    ExecuteScript("nw_c2_default9", OBJECT_SELF);

    // Personal reputation beats faction standing (the smith is Merchant, the
    // guardian Hostile, and repute.fac has those two mutually hostile). bDecays
    // MUST be FALSE -- the default 180s duration would just restart the fight.
    object oBeast = GetObjectByTag("balsum");
    if (GetIsObjectValid(oBeast))
    {
        SetIsTemporaryFriend(oBeast, OBJECT_SELF, FALSE);
        SetIsTemporaryFriend(OBJECT_SELF, oBeast, FALSE);
    }
}

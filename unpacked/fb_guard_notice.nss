//::///////////////////////////////////////////////
//:: fb_guard_notice -- OnPerception for the Kallrist Crypt guardian (badass_2).
//::
//:: A PC carrying the Horn of the Fell Beast has already beaten this boss. The
//:: Kallrist forge is gated on the Horn (fb_no_horn, on the kallrist_forge
//:: StartingList), so waving a horn-bearer through costs nothing and spares
//:: them re-killing a CR333 boss every time they want to visit the anvil --
//:: thematically, the horn is what masters the beast.
//::
//:: Everyone else gets the stock hostile response. Attacking the beast still
//:: breaks the truce the normal way, so this is not a shield.
//::
//:: Set on BOTH badass_2.utc.json and the kallristcryptlow.git.json instance:
//:: this boss respawns from its blueprint (se_respawn_inc.nss), so an
//:: instance-only override would revert on the first death.
//::
//:: Roadmap: the-fell-beast-attacks.
//:://////////////////////////////////////////////

void main()
{
    object oSeen = GetLastPerceived();

    if (GetLastPerceptionSeen() && GetIsPC(oSeen)
        && GetIsObjectValid(GetItemPossessedBy(oSeen, "HornFellBeast")))
    {
        // bDecays FALSE -- a decaying truce would just delay the ambush.
        SetIsTemporaryFriend(oSeen, OBJECT_SELF, FALSE);
        return;
    }

    ExecuteScript("nw_c2_default2", OBJECT_SELF);
}

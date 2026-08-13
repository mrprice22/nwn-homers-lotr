//::///////////////////////////////////////////////
//:: bank_xp_hasbal - StartingConditional: does this account have banked XP?
//::
//:: Gates the "withdraw XP from the family reserve" branch of npc_banker.
//::
//:: WITHDRAWING HAS NO LEVEL REQUIREMENT, deliberately. That branch used to
//:: share bank_xp_hasreq (GetHitDice >= 4) with the RETIRE branch, so a level
//:: 1-3 character could not reach XP its own account already owned - which is
//:: exactly the character that most needs it, and the case the Veteran's
//:: Reward creates on day one of a new season.
//::
//:: The level 4 rule belongs only to the DEPOSIT side (bank_xp_hasreq, still on
//:: the retire node): retiring DELETES the character, and the bar exists so a
//:: fresh character cannot be spun up and retired to launder its 3000 starting
//:: XP. Nothing about withdrawing is destructive or exploitable that way - the
//:: XP was already earned and already taxed on the way in.
//::
//:: Balance rather than TRUE so the option is hidden when the reserve is empty,
//:: instead of leading to a menu with every tier greyed out.
//:://////////////////////////////////////////////
int StartingConditional()
{
    string sCDKey = GetPCPublicCDKey(GetPCSpeaker());
    return GetCampaignInt("bankdb", "fam_xp_" + sCDKey) > 0;
}

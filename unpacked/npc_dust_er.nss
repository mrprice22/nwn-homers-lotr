// Mummy Dust on a five-minute leash -- ScriptEndRound for an NPC caster
//:: (roadmap: gandalfs-mummys)
//
// Reusable OnCombatRoundEnd for any NPC that should summon Mummy Reapers at a
// pace the builder chooses rather than at the pace the stock talent AI chooses.
// Currently wired to gandalf001 (Hobbiton); sarumanthewhi001, ds_gandalf001,
// ds_saruman and gwathsorcerer002 carry spell 637 too and can be moved onto it
// the same way.
//
// WHY THE SPELL COMES OFF THE CREATURE'S SpecAbilityList. An AI-chosen talent
// cannot be rate-limited -- nw_i0_generic picks it whenever it likes, and
// Gandalf's four uses of Epic Mummy Dust went out back to back in the opening
// rounds, which is what UAT reported. Blocking the cast inside the spell script
// would not have helped either: the engine spends the use before the script
// runs, so three of his four summons would simply have been swallowed. Taking
// 637 off his ability list and casting it from here is the only arrangement
// where the gap is exactly the gap, and it does not run out.
//
// Cast with bCheat = TRUE. The caster does hold the feat (Gandalf has 874), but
// a special-ability use only comes back on a rest, so a use-based cast would
// fire a fixed handful of times however long the fight ran. Same reasoning as
// wtop_cmage.nss, which this script is modelled on.
//
// THE COOLDOWN LIVES ON THE AREA, KEYED BY THE CASTER'S TAG. A DelayCommand
// assigned to the area survives the caster's death and respawn, so dying is not
// a way to come back with a fresh summon ready. Keying on the tag rather than
// the object keeps two different casters in one area independent of each other,
// while wtop_cmage.nss deliberately does the opposite (one court-wide pool).
//
// Real seconds, not game hours -- "five minutes" here means five minutes.

const float  NPC_DUST_REFRESH = 300.0;
const string NPC_DUST_CD      = "NPC_CD_DUST_";   // + the caster's tag

// TRUE if this caster's dust is off cooldown, and claims it if so.
int NpcDustClaim(object oArea, string sFlag)
{
    if (GetLocalInt(oArea, sFlag)) return FALSE;

    SetLocalInt(oArea, sFlag, TRUE);
    AssignCommand(oArea,
        DelayCommand(NPC_DUST_REFRESH, DeleteLocalInt(oArea, sFlag)));
    return TRUE;
}

void main()
{
    // The stock combat AI first, untouched -- this script only adds to it.
    ExecuteScript("x2_def_endcombat", OBJECT_SELF);

    object oTarget = GetNearestCreature(CREATURE_TYPE_REPUTATION,
                                        REPUTATION_TYPE_ENEMY, OBJECT_SELF, 1,
                                        CREATURE_TYPE_PLAYER_CHAR,
                                        PLAYER_CHAR_IS_PC);
    if (!GetIsObjectValid(oTarget)) return;
    if (GetIsDead(oTarget)) return;

    if (NpcDustClaim(GetArea(OBJECT_SELF), NPC_DUST_CD + GetTag(OBJECT_SELF)))
    {
        ActionCastSpellAtLocation(SPELL_EPIC_MUMMY_DUST, GetLocation(oTarget),
                                  METAMAGIC_ANY, TRUE);
    }
}

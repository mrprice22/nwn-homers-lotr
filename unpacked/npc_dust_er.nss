// Epic summons on a leash -- ScriptEndRound for an NPC caster
//:: (roadmap: gandalfs-mummys)
//
// Reusable OnCombatRoundEnd for any NPC that should throw its epic SUMMONS at a
// pace the builder chooses rather than at the pace the stock talent AI chooses.
// Currently wired to gandalf001 (Hobbiton); sarumanthewhi001, ds_gandalf001,
// ds_saruman and gwathsorcerer002 carry the same spells and can be moved onto
// it the same way.
//
// Two spells are scripted here, each on its own cooldown:
//
//   SPELL_EPIC_MUMMY_DUST      an Epic Mummy Reaper on the caster's side
//   SPELL_EPIC_DRAGON_KNIGHT   the caster's dragon
//
// WHY THE SPELLS COME OFF THE CREATURE'S SpecAbilityList. An AI-chosen talent
// cannot be rate-limited -- nw_i0_generic picks it whenever it likes, and
// Gandalf's four uses of each went out back to back in the opening rounds
// (UAT rounds 2 and 3). Dragon Knight is the uglier of the two: it is a real
// summon, so each cast unsummons the dragon the previous cast just made, which
// is what UAT watched happen three times in a row. Blocking the cast inside the
// spell script would not have helped either: the engine spends the use before
// the script runs, so most of his summons would simply have been swallowed.
// Taking 637 and 638 off his ability list and casting them from here is the
// only arrangement where the gap is exactly the gap, and it does not run out.
//
// WHY THE SCRIPTED CAST GOES IN *BEFORE* THE STOCK AI, AND AT AN OBJECT.
// This script used to chain x2_def_endcombat first and then queue the cast, the
// way wtop_cmage.nss does, and Gandalf never summoned a single mummy (UAT round
// 3). Two reasons, both in nw_i0_generic:
//
//   * DetermineCombatRound clears the action queue when it decides to act, so a
//     cast appended AFTER it is still sitting behind the AI's own action when
//     the next round wipes the queue. With a book as deep as Gandalf's the AI
//     acts every round, so that cast never once reached the front. The cast now
//     goes first, on its own ClearAllActions, and the AI is skipped for that
//     round -- it picks up again on the next one.
//   * DetermineCombatRound only protects a cast in progress when
//     GetAttemptedSpellTarget() is valid, which an ActionCastSpellAtLocation
//     never sets. Cast AT THE TARGET OBJECT instead: the spell scripts read
//     GetSpellTargetLocation(), which resolves to that object's location, and
//     the AI now leaves the cast alone while it finishes. The extra guard below
//     (return while ACTION_CASTSPELL) closes the same hole from this side.
//
// Cast with bCheat = TRUE. The caster does hold the feats (Gandalf has 874 and
// 875), but a special-ability use only comes back on a rest, so a use-based
// cast would fire a fixed handful of times however long the fight ran. Same
// reasoning as wtop_cmage.nss, which this script is modelled on.
//
// THE COOLDOWNS LIVE ON THE AREA, KEYED BY THE CASTER'S TAG. A DelayCommand
// assigned to the area survives the caster's death and respawn, so dying is not
// a way to come back with a fresh summon ready. Keying on the tag rather than
// the object keeps two different casters in one area independent of each other,
// while wtop_cmage.nss deliberately does the opposite (one court-wide pool).
//
// Real seconds, not game hours -- "five minutes" here means five minutes.

const float  NPC_DUST_REFRESH   = 300.0;
const float  NPC_KNIGHT_REFRESH = 300.0;
const string NPC_DUST_CD        = "NPC_CD_DUST_";     // + the caster's tag
const string NPC_KNIGHT_CD      = "NPC_CD_KNIGHT_";   // + the caster's tag

// TRUE if this caster's spell is off cooldown, and claims it if so.
int NpcDustClaim(object oArea, string sFlag, float fRefresh)
{
    if (GetLocalInt(oArea, sFlag)) return FALSE;

    SetLocalInt(oArea, sFlag, TRUE);
    AssignCommand(oArea,
        DelayCommand(fRefresh, DeleteLocalInt(oArea, sFlag)));
    return TRUE;
}

void main()
{
    // Mid-cast: leave it alone. Running the AI here is what interrupts it.
    if (GetCurrentAction(OBJECT_SELF) == ACTION_CASTSPELL) return;

    object oTarget = GetNearestCreature(CREATURE_TYPE_REPUTATION,
                                        REPUTATION_TYPE_ENEMY, OBJECT_SELF, 1,
                                        CREATURE_TYPE_PLAYER_CHAR,
                                        PLAYER_CHAR_IS_PC);

    if (GetIsObjectValid(oTarget) && !GetIsDead(oTarget))
    {
        object oArea  = GetArea(OBJECT_SELF);
        string sTag   = GetTag(OBJECT_SELF);

        // One scripted cast per round, mummy first: it is the summon that
        // stays, and the dragon is the one that replaces itself.
        if (NpcDustClaim(oArea, NPC_DUST_CD + sTag, NPC_DUST_REFRESH))
        {
            ClearAllActions();
            ActionCastSpellAtObject(SPELL_EPIC_MUMMY_DUST, oTarget,
                                    METAMAGIC_ANY, TRUE);
            return;
        }

        if (NpcDustClaim(oArea, NPC_KNIGHT_CD + sTag, NPC_KNIGHT_REFRESH))
        {
            ClearAllActions();
            ActionCastSpellAtObject(SPELL_EPIC_DRAGON_KNIGHT, oTarget,
                                    METAMAGIC_ANY, TRUE);
            return;
        }
    }

    // Nothing scripted this round -- the stock combat AI, untouched.
    ExecuteScript("x2_def_endcombat", OBJECT_SELF);
}

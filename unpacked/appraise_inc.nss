// appraise_inc.nss - shared Appraise-skill scaling helpers.
//
// Used by the Forge of Wonders (raises the max gold value an item may be
// enchanted to, and the lawful contraband ceiling) and by the merchant system
// (raises the max gold a capped store will pay a player when selling).
//
// The skill is read deterministically - players always "take 20" rather than
// rolling a d20 - so the same character always sees the same benefit.
//
// NWScript has no include guards; consumer scripts may #include this alongside
// other includes. Define nothing here that another include also defines.

// "Take 20": the flat 20 everyone gets for free on a skill check.
const int APPRAISE_TAKE20     = 20;
// First check value that earns ANY bonus over the current module defaults.
// A character with no Appraise investment lands at check 20 (take-20 + 0
// effective ranks) and gets exactly today's pricing/ceilings; you need at
// least 1 effective Appraise point (one rank, or a +1 Charisma modifier, or an
// Appraise item) to push the check to 21 and start earning a bonus.
const int APPRAISE_MIN_CHECK  = 21;
// Check value that grants the full bonus. ~43 ranks (level-40 class skill) +
// take-20 + ~+2 from a modest Charisma modifier / Appraise item.
const int APPRAISE_FULL_CHECK = 65;

// Deterministic "take 20" Appraise check for oPC. GetSkillRank returns the
// effective rank (ranks + ability modifier + feats + gear), so Charisma and any
// Appraise-boosting item are already folded in.
int AppraiseCheck(object oPC)
{
    return APPRAISE_TAKE20 + GetSkillRank(SKILL_APPRAISE, oPC);
}

// Linear bonus in [0, nMax]. Zero at (or below) the bare take-20 floor, so an
// uninvested character is no better off than today; scales up from check 21 and
// reaches the full nMax at check APPRAISE_FULL_CHECK. Anchored at the take-20
// floor so the first earned point (check 21) yields the smallest non-zero step.
int AppraiseBonusScaled(object oPC, int nMax)
{
    int nCheck = AppraiseCheck(oPC);
    if (nCheck < APPRAISE_MIN_CHECK) return 0;
    if (nCheck >= APPRAISE_FULL_CHECK) return nMax;
    return (nCheck - APPRAISE_TAKE20) * nMax
        / (APPRAISE_FULL_CHECK - APPRAISE_TAKE20);
}

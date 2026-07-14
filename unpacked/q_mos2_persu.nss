// The Miller's Other Son -- rolls the single Persuade attempt (DC 18, per
// the design note: d20 + Persuade rank). Marks the attempt as spent
// (persistent, one try per character) and stashes the result in a
// session-local int that the two follow-up entries branch on
// (q_mos2_persc selects the success line; the failure line is the
// fallback and turns the cult leader hostile).
void main()
{
    object oPC = GetPCSpeaker();
    SetCampaignInt("mos2", "tried", 1, oPC);

    int nRoll = d20() + GetSkillRank(SKILL_PERSUADE, oPC);
    if (nRoll >= 18)
        SetLocalInt(oPC, "mos2_persuade", 1);
    else
        SetLocalInt(oPC, "mos2_persuade", 2);
}

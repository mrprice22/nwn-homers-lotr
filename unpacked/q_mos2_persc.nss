// The Miller's Other Son -- StartingConditional: the Persuade roll just made
// in q_mos2_persu succeeded. Selects the cult leader's climb-down line.
int StartingConditional()
{
    return GetLocalInt(GetPCSpeaker(), "mos2_persuade") == 1;
}

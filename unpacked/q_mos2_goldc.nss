// The Miller's Other Son -- StartingConditional: the player can afford the
// peddler's 10 gp "coin for the telling".
int StartingConditional()
{
    return GetGold(GetPCSpeaker()) >= 10;
}

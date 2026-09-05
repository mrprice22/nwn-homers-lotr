// merit_graf_ok.nss - StartingConditional gating the "Yes, that's the one" reply
// on there actually being a selection. Mirrors merit_ci_dm.nss.
int StartingConditional()
{
    return GetLocalInt(GetPCSpeaker(), "merit_graf_ok");
}

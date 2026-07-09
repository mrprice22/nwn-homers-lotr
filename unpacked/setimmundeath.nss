// Forge option param setter: "Deathless" — immunity to Death Magic.
// Pairs with setpropmiscimmun (MODIFY_PROPERTY = "Miscellaneous Immunity").
void main()
{
    SetLocalInt(GetPCSpeaker(), "MODIFY_PARAM3", IP_CONST_IMMUNITYMISC_DEATH_MAGIC);
}

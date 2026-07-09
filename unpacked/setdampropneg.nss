void main()
{
    object oPC = GetPCSpeaker();
    SetLocalString(oPC, "MODIFY_PROPERTY", "Damage Bonus");
    SetLocalInt(oPC, "MODIFY_PARAM2", IP_CONST_DAMAGETYPE_NEGATIVE);
}

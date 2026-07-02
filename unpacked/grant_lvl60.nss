void main()
{
    object oPC = GetPCSpeaker();
    if (!GetIsPC(oPC)) return;
    SetXP(oPC, 3581000);
    FloatingTextStringOnCreature("XP set to 3581000.", oPC, FALSE);
}

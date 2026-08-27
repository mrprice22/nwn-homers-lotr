// Kallrist Crypt forge - the defensive half of the crypt's negative-energy
// signature. Mirrors setdampropneg.nss (which binds the grave-chill to a
// weapon's edge); this one wards worn gear against it instead.
//
// Sets BOTH halves of the property up front - the property name and the damage
// type - so the shared setdamresistNN leaves supply only MODIFY_PARAM3 and need
// no Kallrist-specific variants. GetNewProperty() in itemprocs.nss then builds
// ItemPropertyDamageResistance(PARAM2, PARAM3) unchanged.
//
// The menu link that runs this is gated by isnotweapon: the edge is for weapons,
// the ward is for everything you wear.
void main()
{
    object oPC = GetPCSpeaker();
    SetLocalString(oPC, "MODIFY_PROPERTY", "Damage Resistance");
    SetLocalInt(oPC, "MODIFY_PARAM2", IP_CONST_DAMAGETYPE_NEGATIVE);
}

// Forge option param setter: "Voidshield" - immunity to the Implosion spell.
// Pairs with setspellimmun (MODIFY_PROPERTY = "Spell Immunity Specific");
// GetNewProperty -> ItemPropertySpellImmunitySpecific(IP_CONST_IMMUNITYSPELL_IMPLOSION).
void main()
{
    SetLocalInt(GetPCSpeaker(), "MODIFY_PARAM3", IP_CONST_IMMUNITYSPELL_IMPLOSION);
}

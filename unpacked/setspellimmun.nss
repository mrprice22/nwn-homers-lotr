// Forge option setter: select the "Immunity: Specific Spell" item property.
// The concrete spell subtype (an IP_CONST_IMMUNITYSPELL_* value) is supplied by a
// companion setter that writes MODIFY_PARAM3 (e.g. setimplosion).
// Dispatched by GetNewProperty in itemprocs.nss -> ItemPropertySpellImmunitySpecific.
void main()
{
    SetLocalString(GetPCSpeaker(), "MODIFY_PROPERTY", "Spell Immunity Specific");
}

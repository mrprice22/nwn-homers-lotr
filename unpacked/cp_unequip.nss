// cp_unequip -- Crash Party: module OnPlayerUnEquipItem hook.
//
// Mirror of cp_equip.nss; see that file for why this is a cp_-only dispatcher
// rather than the module-wide x2_mod_def_unequ.
//
// Taking a worn party item off has to stop whatever it started, so this is not
// optional decoration: without it the Crown would keep making noise out of an
// empty head slot until the player logged out.

const string CP_WORN_ON = "cp_worn_on";

void main()
{
    object oPC   = GetPCItemLastUnequippedBy();
    object oItem = GetPCItemLastUnequipped();
    if (!GetIsObjectValid(oPC) || !GetIsObjectValid(oItem)) return;

    // Harvest of Shadows prizes (hw26_*, hw27_*...): their worn auras and
    // glows are re-synced from what the PC actually has on.
    if (GetStringLeft(GetResRef(oItem), 3) == "hw2")
    {
        ExecuteScript("hw_fx_refresh", oPC);
        return;
    }

    if (GetStringLeft(GetResRef(oItem), 3) != "cp_") return;

    DeleteLocalInt(oPC, CP_WORN_ON);
    ExecuteScript(GetResRef(oItem), oPC);
}

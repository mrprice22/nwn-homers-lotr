// cp_equip -- Crash Party: module OnPlayerEquipItem hook.
//
// ## Why a new script instead of wiring x2_mod_def_equ
//
// Mod_OnPlrEqItm has always been EMPTY in this module, so there is no equip
// behaviour to preserve -- but the obvious move, pointing it at the shipped
// x2_mod_def_equ, would switch on tag-based EQUIP dispatch for ALL ~3000 items
// at once. Any item whose Tag happens to match an existing script name would
// start firing it on equip, module-wide, with no way to predict which. That is
// a large blast radius for two joke hats.
//
// So this dispatches cp_* and nothing else, exactly like the prefix branch in
// dmfi_activate.nss. If the module ever wants real tag-based equip scripting,
// that is a separate decision made on purpose.
//
// The worn item's own script handles both directions and reads CP_WORN_ON to
// tell them apart, so each item stays in one file.

const string CP_WORN_ON = "cp_worn_on";

void main()
{
    object oPC   = GetPCItemLastEquippedBy();
    object oItem = GetPCItemLastEquipped();
    if (!GetIsObjectValid(oPC) || !GetIsObjectValid(oItem)) return;
    if (GetStringLeft(GetResRef(oItem), 3) != "cp_") return;

    SetLocalInt(oPC, CP_WORN_ON, TRUE);
    ExecuteScript(GetResRef(oItem), oPC);
}

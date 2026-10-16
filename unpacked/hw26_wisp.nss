// hw26_wisp - Ghost-Lantern Charm: switch the orbiting wisp on or off. The
// choice lives on the item (item locals persist in the character file), and
// HW_RefreshPrizeFx puts the wisp back after every login, death or respawn.

#include "hw_inc"

void main()
{
    object oPC = OBJECT_SELF;
    if (!GetIsPC(oPC)) return;
    object oItem = GetLocalObject(oPC, "hw_item");
    int bOn = !GetLocalInt(oItem, "hw_on");
    SetLocalInt(oItem, "hw_on", bOn);
    HW_RefreshPrizeFx(oPC);
    FloatingTextStringOnCreature(bOn ? "The ghost-lantern flickers awake."
                                     : "The ghost-lantern gutters out.", oPC, FALSE);
}

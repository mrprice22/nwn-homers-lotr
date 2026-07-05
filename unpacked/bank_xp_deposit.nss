#include "nwnx_admin"

void main()
{
object oPC = GetPCSpeaker();
string sCDKey = GetPCPublicCDKey(oPC);

if(GetHitDice(oPC) < 4)
{
    FloatingTextStringOnCreature("You must reach level 4 before the bank will accept your retirement.", oPC, FALSE);
    SendMessageToPC(oPC, "Come back once your character has reached level 4 -- the bank does not accept starting funds alone.");
    return;
}

// Place the retirement marker first — also acts as an inventory-space check.
// CreateItemOnObject returns OBJECT_INVALID if the inventory is full.
object oMarker = CreateItemOnObject("bank_xp_retired", oPC);
if(!GetIsObjectValid(oMarker))
{
    FloatingTextStringOnCreature("Oops!  You need to make room in your inventory first.", oPC, FALSE);
    SendMessageToPC(oPC, "Your inventory is too full to proceed.  Please make room for at least one item and try again.");
    return;
}

// Exclude the 3000 starting XP grant from the bank fee -- only earned XP
// is subject to the 15% fee. Clamped so it can never go negative.
int iBankableXP = GetXP(oPC) - 3000;
if(iBankableXP < 0) iBankableXP = 0;

// 85% of bankable XP, integer division rounds down automatically
int iXPToBank = (iBankableXP * 85) / 100;

// Transfer all gold to family gold account
int iGold = GetGold(oPC);
if(iGold > 0)
{
    int iFamGP = GetCampaignInt("bankdb", "fam_bankgp_" + sCDKey);
    TakeGoldFromCreature(iGold, oPC);
    SetCampaignInt("bankdb", "fam_bankgp_" + sCDKey, iFamGP + iGold);
}

// Add XP to family XP reserve
int iFamXP = GetCampaignInt("bankdb", "fam_xp_" + sCDKey);
SetCampaignInt("bankdb", "fam_xp_" + sCDKey, iFamXP + iXPToBank);

// Destroy equipped items (slots 0-13 cover all player equipment)
int i;
for(i = 0; i < 14; i++)
{
    object oItem = GetItemInSlot(i, oPC);
    if(GetIsObjectValid(oItem))
    {
        SetPlotFlag(oItem, FALSE);
        DestroyObject(oItem);
    }
}

// Destroy inventory items, preserving the retirement marker as a failsafe
object oItem = GetFirstItemInInventory(oPC);
while(GetIsObjectValid(oItem))
{
    object oNext = GetNextItemInInventory(oPC);
    if(GetTag(oItem) != "bank_xp_retired")
    {
        SetPlotFlag(oItem, FALSE);
        DestroyObject(oItem);
    }
    oItem = oNext;
}

// Zero XP, export the stripped state, then delete the character file.
// The marker item left in the .bic acts as a fallback ban if NWNX delete fails
// and the player somehow reconnects — asc_enter.nss will catch and boot them.
SetXP(oPC, 0);
ExportSingleCharacter(oPC);

string sMsg = "This character has been permanently retired through the XP Bank.  "
    + IntToString(iXPToBank) + " XP has been deposited into your family reserve.  "
    + IntToString(iGold) + " gold has been transferred to your family gold account.";

NWNX_Administration_DeletePlayerCharacter(oPC, FALSE, sMsg);
}

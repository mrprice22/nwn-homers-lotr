// Well of Eru OnEnter
// - Sends a welcome message and gives 3000 starter XP to brand-new characters.
// - Stocks the Donations Chest once per server reset with:
//     * Loot from a randomly selected good-side city (Guardian of Light list)
//     * Loot from a randomly selected evil-side city (Guardian of Darkness list)
//     * Two random bonus items drawn from the obtainable custom item pool
#include "_inc_donations"
#include "forge_inc"

// Creates an item and immediately identifies it.
object CreateIDItem(string sResRef, object oTarget, int nStackSize = 1)
{
    object oItem = CreateItemOnObject(sResRef, oTarget, nStackSize);
    SetIdentified(oItem, TRUE);
    return oItem;
}

// --- helper: good-side city loot ---
void SpawnGoodCityLoot(object oChest, int nCity)
{
    switch (nCity)
    {
        case 0: // Gondor
            // Gondorian Bowman (8) vs Epic Gondorian Guardsman (2)
            if (Random(2) == 0)
                CreateIDItem("boltoftheblackel", oChest, 99);
            else {
                CreateIDItem("nw_it_mpotion009", oChest);
                CreateIDItem("nw_it_mpotion016", oChest);
            }
            break;

        case 1: // Helms Deep
            // Helm's Deep Elite Guard (6) vs Defender of the Deep (6)
            if (Random(2) == 0) {
                CreateIDItem("nw_it_mpotion003", oChest, 2);
                CreateIDItem("nw_it_mpotion009", oChest, 2);
            } else
                CreateIDItem("012", oChest);      // Helm of the Defender
            break;

        case 2: // Rivendell
            // Forest Guardian of Rivendell (6)
            CreateIDItem("eyesoftheforest", oChest);
            CreateIDItem("nw_it_mbelt021",  oChest);
            break;

        case 3: // Lothlorien
            // Galadhrim Arcane Archer (12) vs Galadhrim Shield Guardian (11)
            if (Random(2) == 0)
                CreateIDItem("wammar029", oChest, 99);    // Cold Arrows
            else {
                CreateIDItem("nw_it_mpotion016", oChest);
                CreateIDItem("nw_it_mpotion005", oChest);
            }
            break;

        case 4: // Edoras
            // Ridermark Guardian (8)
            CreateIDItem("nw_it_mpotion012", oChest);
            CreateIDItem("nw_it_mpotion015", oChest);
            CreateIDItem("nw_it_mpotion009", oChest);
            CreateIDItem("nw_it_mpotion016", oChest);
            break;
    }
}

// --- helper: evil-side city loot ---
void SpawnEvilCityLoot(object oChest, int nCity)
{
    switch (nCity)
    {
        case 0: // Morannan / Black Gate
            // Archer of Mordor (12)
            CreateIDItem("wammar055", oChest, 99);        // Mordor Slayers
            break;

        case 1: // Isengard
            // Dunlending Shock Trooper (5)
            CreateIDItem("nw_it_mpotion004", oChest);
            CreateIDItem("nw_it_mpotion003", oChest);
            CreateIDItem("nw_it_mpotion014", oChest);
            CreateIDItem("gauntletsofdexte", oChest);     // Gauntlets of Dex +6
            break;

        case 2: // Cirith Ungol
            // Mordor Orc Snaker (4) vs Mordor Slaughterer (3)
            CreateIDItem("nw_it_mpotion015", oChest);
            CreateIDItem("nw_it_mpotion003", oChest);
            if (Random(2) == 0)
                CreateIDItem("mordoraxe", oChest);
            break;

        case 3: // Carn Dum
            // Black Numenorean Militia (6)
            CreateIDItem("nw_it_mpotion009", oChest);
            CreateIDItem("nw_it_mpotion013", oChest);
            break;
    }
}

// Moves a single illicit item into the quarantine chest campaign DB,
// refunds 5x its GP value, and notifies the player.
void QuarantineIllicitItem(object oItem, object oPC)
{
    string sName  = GetName(oItem);
    int    nValue = GetGoldPieceValue(oItem);
    int    nComp  = nValue * 5;

    string sLog = "Illicit donations item '" + sName + "' (resref: " + GetResRef(oItem)
                + ") reclaimed from " + GetName(oPC) + "; refunded " + IntToString(nComp) + " gp (5x value).";

    // Stamp provenance onto the item so it persists in the quarantine chest
    // snapshot until a DM removes it (the quarantine_*_info row is cleared as
    // soon as the chest is opened - see zep_cr_qrestore.nss).
    SetLocalString(oItem, "QUARANTINE_INFO", sLog);

    int nQ = GetCampaignInt("craftdb", "quarantine_count");
    StoreCampaignObject("craftdb", "quarantine_" + IntToString(nQ), oItem);
    SetCampaignString("craftdb", "quarantine_" + IntToString(nQ) + "_info", sLog);
    SetCampaignInt("craftdb", "quarantine_count", nQ + 1);
    DestroyObject(oItem);

    WriteTimestampedLogEntry(sLog);
    SendMessageToAllDMs(sLog);
    GiveGoldToCreature(oPC, nComp);
    SendMessageToPC(oPC,
        "[Donations Chest] We owe you an apology. '" + sName + "' was mistakenly "
        + "included in the Donations Chest and should never have been accessible to players. "
        + "We have secured it in the House of Homer. As compensation for the emotional damage "
        + "of losing such great gear, you have been credited " + IntToString(nComp) + " gold pieces "
        + "(5x its appraised value). We are truly sorry for the inconvenience!");
}

// Scans all inventory and equipment slots for illicit donations items and quarantines them.
void ScanForIllicitItems(object oPC)
{
    int nSlot;
    for (nSlot = 0; nSlot < NUM_INVENTORY_SLOTS; nSlot++)
    {
        object oItem = GetItemInSlot(nSlot, oPC);
        if (GetIsObjectValid(oItem) && IsIllicitDonationsItem(GetResRef(oItem)))
            QuarantineIllicitItem(oItem, oPC);
    }

    object oItem = GetFirstItemInInventory(oPC);
    while (GetIsObjectValid(oItem))
    {
        object oNext = GetNextItemInInventory(oPC);
        if (IsIllicitDonationsItem(GetResRef(oItem)))
            QuarantineIllicitItem(oItem, oPC);
        oItem = oNext;
    }
}

// --- stock the chest once per server reset ---
void StockDonationsChest()
{
    object oMod = GetModule();
    if (GetLocalInt(oMod, "DONATIONS_STOCKED")) return;
    SetLocalInt(oMod, "DONATIONS_STOCKED", 1);

    object oChest = GetObjectByTag("x2_easy_Chest2ff");
    if (!GetIsObjectValid(oChest)) return;

    // Random good-side city: 0=Gondor 1=Helms Deep 2=Rivendell 3=Lothlorien 4=Edoras
    SpawnGoodCityLoot(oChest, Random(5));
    // Random evil-side city: 0=Black Gate 1=Isengard 2=Cirith Ungol 3=Carn Dum
    SpawnEvilCityLoot(oChest, Random(4));

    // Two distinct bonus items from the full 200k-500k custom item pool
    int nPoolSize = BONUS_POOL_SIZE;
    int nPick1 = Random(nPoolSize);
    int nPick2 = Random(nPoolSize - 1);
    if (nPick2 >= nPick1) nPick2++;     // guarantee nPick2 != nPick1

    string sItem1 = GetBonusItemResref(nPick1);
    string sItem2 = GetBonusItemResref(nPick2);
    if (sItem1 != "") CreateIDItem(sItem1, oChest, GetBonusItemStackSize(nPick1));
    if (sItem2 != "") CreateIDItem(sItem2, oChest, GetBonusItemStackSize(nPick2));
}

void main()
{
    // Keep creatures in their spawn area (anti-kiting); see leash_to_area.nss.
    ExecuteScript("leash_to_area", OBJECT_SELF);

    object oPC = GetEnteringObject();

    // Starter XP + welcome message for brand-new characters
    if (!GetIsDM(oPC) && GetXP(oPC) == 0)
    {
        GiveXPToCreature(oPC, 3000);
        SendMessageToPC(oPC, "Welcome to Homer's Legendary Lord of the Rings!");
        SendMessageToPC(oPC, "The light of Eru smiles upon you, new adventurer. "
            + "You have been granted 3000 experience points to begin your journey. "
            + "Check the Donations Chest near the Well Mart - it may hold something "
            + "useful to help you on your way. Good luck, and may your path through "
            + "Middle-earth be legendary!");
    }

    if (!GetIsDM(oPC) && GetIsPC(oPC))
    {
        ScanForIllicitItems(oPC);

        // Give the Bestiary book once per character (activate it to view your
        // creature-kill records). Plot item, so it can't be dropped or sold.
        // Granted BEFORE the contraband sweep so a scan failure can never eat
        // the grant (and harmless if the sweep then jails/teleports the PC).
        if (!GetIsObjectValid(GetItemPossessedBy(oPC, "bestiarybook")))
            CreateItemOnObject("bestiarybook", oPC);

        // Illegally forged gear (tampered + over 6 props / 750k value) lands
        // the bearer in the Pit Prison until a Forge Warden strips it legal.
        // Chunked scan (one item per delayed step) so a full inventory can't
        // blow the script instruction cap; already-verified items are skipped.
        ForgeBeginScan(oPC);
    }

    StockDonationsChest();
}

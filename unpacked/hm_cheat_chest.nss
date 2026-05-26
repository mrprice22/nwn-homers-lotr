void main()
{
    object oPC = GetLastUsedBy();
    if (!GetIsPC(oPC)) return;

    string sKey = GetPCPublicCDKey(oPC);
    int bAuth =   (sKey == "FT6RKMX4")   // Homer
               || (sKey == "QR69DAFR")   // Homeless
               || (sKey == "FTM47TW9")   // Cassy
               || (sKey == "QG6QKQV3");  // Popoe

    if (!bAuth)
    {
        SendMessageToPC(oPC, "This chest is not for you.");
        return;
    }

    if (GetItemPossessedBy(oPC, "mw_mixtape")        == OBJECT_INVALID) CreateItemOnObject("mw_mixtape",       oPC);
    if (GetItemPossessedBy(oPC, "superdeluxe")        == OBJECT_INVALID) CreateItemOnObject("superdeluxering",  oPC);
    if (GetItemPossessedBy(oPC, "X0_CLOTH004")        == OBJECT_INVALID) CreateItemOnObject("cloth005",         oPC);
    if (GetItemPossessedBy(oPC, "DenethorsPlate")     == OBJECT_INVALID) CreateItemOnObject("denethorsplat001", oPC);
    if (GetItemPossessedBy(oPC, "Theuntouchable")     == OBJECT_INVALID) CreateItemOnObject("theuntouchable",   oPC);
    if (GetItemPossessedBy(oPC, "EvilDeathShield")    == OBJECT_INVALID) CreateItemOnObject("evildeathshield",  oPC);
    if (GetItemPossessedBy(oPC, "BossRing")           == OBJECT_INVALID) CreateItemOnObject("bossring001",      oPC);
    if (GetItemPossessedBy(oPC, "SuperKama")          == OBJECT_INVALID) CreateItemOnObject("item082",          oPC);
    if (GetItemPossessedBy(oPC, "HomersTouch")        == OBJECT_INVALID) CreateItemOnObject("item068",          oPC);
    if (GetItemPossessedBy(oPC, "X0_IT_MNECK001dds")  == OBJECT_INVALID) CreateItemOnObject("it_mneck002",      oPC);
    if (GetItemPossessedBy(oPC, "StaffofHomer")       == OBJECT_INVALID) CreateItemOnObject("staffofhomer",     oPC);
    if (GetItemPossessedBy(oPC, "SommanusAxe")        == OBJECT_INVALID) CreateItemOnObject("sommanusaxe",      oPC);
    if (GetItemPossessedBy(oPC, "ZOMGWTFBBQHAX")      == OBJECT_INVALID) CreateItemOnObject("zomgwtfbbqhax",    oPC);
    if (GetItemPossessedBy(oPC, "homerclaw")          == OBJECT_INVALID) CreateItemOnObject("it_crewpsp024",    oPC);
    if (GetItemPossessedBy(oPC, "Maghicaepic")        == OBJECT_INVALID) CreateItemOnObject("jubmaghica001",    oPC);
    if (GetItemPossessedBy(oPC, "SmashsSword")        == OBJECT_INVALID) CreateItemOnObject("item061",          oPC);
    if (GetItemPossessedBy(oPC, "x0_misc_fists")     == OBJECT_INVALID) CreateItemOnObject("x0_misc_fists",    oPC);

    SendMessageToPC(oPC, "Your items have been placed in your inventory.");
}

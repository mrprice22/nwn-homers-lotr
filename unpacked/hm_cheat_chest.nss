#include "admin_db"

void main()
{
    object oPC = GetLastUsedBy();
    if (!GetIsPC(oPC)) return;

    // Whitelist lives in the "admindb" campaign database (admins.can_chest),
    // not in source - keys never ship inside the .mod.
    int bAuth = Admin_CanChest(oPC);

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
    if (GetItemPossessedBy(oPC, "ElrondsWrit")       == OBJECT_INVALID) CreateItemOnObject("elrondswrit",      oPC);
    if (GetItemPossessedBy(oPC, "Forgekey")          == OBJECT_INVALID) CreateItemOnObject("forgekey",         oPC);
    if (GetItemPossessedBy(oPC, "ammoreplicator")    == OBJECT_INVALID) CreateItemOnObject("ammoreplicator",   oPC);

    // Two Keys of the Hidden Court, unconditionally rather than guarded:
    // the sealed door under Amon Sul is AutoRemoveKey and eats one key per
    // crossing, so a single key is a one-way trip into the court.
    // Two separate creates, not a stack of 2 - BaseItem 65 (key) does not
    // stack, and CreateItemOnObject clamps to baseitems.2da Stacking.
    CreateItemOnObject("wtop_4key_whole", oPC);
    CreateItemOnObject("wtop_4key_whole", oPC);

    // Rapid-testing supply: always hand out 3 more Runes of Expansion
    // (consumable, so no possession guard).
    // ONE create per rune: slot_token is BaseItem 24 (miscsmall), Stacking 1 in
    // baseitems.2da, and CreateItemOnObject clamps its stack argument to that -
    // so the old "3" quietly handed out one. See CLAUDE-gotchas.md.
    int nRune;
    for (nRune = 0; nRune < 3; nRune++)
        CreateItemOnObject("slot_token", oPC);

    SendMessageToPC(oPC, "Your items have been placed in your inventory.");
}

// hw_pking_death - the Pumpkin King falls.
//
// A heap of Pumpkin Guts, a chance at a Jack-o'-Lantern, a server-wide shout,
// and he rises again an hour later somewhere else in the marsh. SE_NO_RESPAWN
// keeps the module's own respawn off him (he is not a placed creature).

#include "hw_inc"

void main()
{
    object oKing = OBJECT_SELF;
    if (GetLocalInt(oKing, "hw_dead")) return;   // OnDeath can repeat; pay once
    SetLocalInt(oKing, "hw_dead", 1);
    location l = GetLocation(oKing);

    object oKiller = GetLastKiller();
    while (GetIsObjectValid(GetMaster(oKiller))) oKiller = GetMaster(oKiller);

    // 25 guts to every party member nearby, straight into the pack. The
    // occasional Jack-o'-Lantern Charm drops to the ground so the party loot
    // roll decides who keeps it.
    HW_GiveGuts(oKiller, l, HW_KING_GUTS);
    if (Random(100) < 20)
        CreateObject(OBJECT_TYPE_ITEM, "hw26_charm", l);
    ApplyEffectAtLocation(DURATION_TYPE_INSTANT, EffectVisualEffect(VFX_FNF_PWKILL), l);

    // His army dies with him: a respawned King starts with no leftovers. Not
    // kills, so no guts and no pumpkins.
    int i = 0;
    object oSk = GetObjectByTag(HW_TAG_SKEL, i);
    while (GetIsObjectValid(oSk))
    {
        if (GetLocalInt(oSk, "hw_army") && !GetIsDead(oSk))
        {
            ApplyEffectAtLocation(DURATION_TYPE_INSTANT,
                EffectVisualEffect(VFX_IMP_DEATH_L), GetLocation(oSk));
            DestroyObject(oSk, 0.3);
        }
        oSk = GetObjectByTag(HW_TAG_SKEL, ++i);
    }

    string sMsg = COLOR_ORANGE + "[Harvest of Shadows] The Pumpkin King has been cut down"
        + (GetIsPC(oKiller) ? " by " + GetName(oKiller) : "")
        + " in the Dead Marshes! He will rise again within the hour." + COLOR_END;
    object oP = GetFirstPC();
    while (GetIsObjectValid(oP))
    {
        SendMessageToPC(oP, sMsg);
        oP = GetNextPC();
    }

    AssignCommand(GetModule(), DelayCommand(HW_KING_RESPAWN, HW_SpawnKing()));
    ExecuteScript("nw_c2_default7", oKing);
}

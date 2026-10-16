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

    // 10 guts to every party member nearby, straight into the pack. The
    // occasional Jack-o'-Lantern Charm drops to the ground so the party loot
    // roll decides who keeps it.
    HW_GiveGuts(oKiller, l, 10);
    if (Random(100) < 20)
        CreateObject(OBJECT_TYPE_ITEM, "hw26_charm", l);
    ApplyEffectAtLocation(DURATION_TYPE_INSTANT, EffectVisualEffect(VFX_FNF_PWKILL), l);

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

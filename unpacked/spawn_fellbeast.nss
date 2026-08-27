#include "NW_O2_CONINCLUDE"
#include "NW_I0_GENERIC"

void main()
{
    // Record spawn area so the creature can be leashed to it (see leash_to_area.nss).
    SetLocalLocation(OBJECT_SELF, "spawn", GetLocation(OBJECT_SELF));

    // Bestiary kill-tracking: install the OnDamaged/OnDeath wrappers (idempotent).
    ExecuteScript("bst_install", OBJECT_SELF);

    // --- Kalrun the Deathless is not prey (roadmap: the-fell-beast-attacks) ---
    // The guardian is Hostile (faction 1) and the crypt smith is a Merchant
    // (faction 3), and Hostile<->Merchant sits at 0 in repute.fac, so Kalrun is
    // a legitimate target standing ~6m from the spawn point. He is also Plot: 1
    // and so can never die -- the beast's aggro never resolves and it duels him
    // forever instead of engaging the player. Personal reputation overrides
    // faction standing, which fixes it without touching the reputation matrix
    // (Kalrun stays a normal Merchant to everyone else). bDecays MUST be passed
    // FALSE explicitly: the default duration is 180s and would simply restart
    // the fight three minutes later.
    object oSmith = GetObjectByTag("KallristSmith");
    if (GetIsObjectValid(oSmith))
    {
        SetIsTemporaryFriend(oSmith, OBJECT_SELF, FALSE);
        SetIsTemporaryFriend(OBJECT_SELF, oSmith, FALSE);
    }

    // --- Horn-bearers pass unmolested (roadmap: the-fell-beast-attacks) ---
    // A player who already holds the Horn has beaten this fight; the forge is
    // gated on the Horn (fb_no_horn on the kallrist_forge StartingList), so
    // letting them walk to the anvil costs nothing and saves re-killing a CR333
    // boss for a shop visit. This catches PCs already standing in the area at
    // (re)spawn time; fb_guard_notice catches the ones who walk in later.
    object oPC = GetFirstObjectInArea(GetArea(OBJECT_SELF));
    while (GetIsObjectValid(oPC))
    {
        if (GetIsPC(oPC) && GetIsObjectValid(GetItemPossessedBy(oPC, "HornFellBeast")))
            SetIsTemporaryFriend(oPC, OBJECT_SELF, FALSE);
        oPC = GetNextObjectInArea(GetArea(OBJECT_SELF));
    }

    effect eVis = EffectVisualEffect(VFX_DUR_PROT_SHADOW_ARMOR);
    effect eVis1 = EffectVisualEffect(VFX_DUR_GLOW_BROWN);


    ApplyEffectToObject(DURATION_TYPE_PERMANENT, eVis, OBJECT_SELF);
    ApplyEffectToObject(DURATION_TYPE_PERMANENT, eVis1, OBJECT_SELF);


// DEFAULT GENERIC BEHAVIOR (DO NOT TOUCH) *****************************************************************************************
    SetListeningPatterns();    // Goes through and sets up which shouts the NPC will listen to.
    WalkWayPoints();           // Optional Parameter: void WalkWayPoints(int nRun = FALSE, float fPause = 1.0)
                               // 1. Looks to see if any Way Points in the module have the tag "WP_" + NPC TAG + "_0X", if so walk them
                               // 2. If the tag of the Way Point is "POST_" + NPC TAG the creature will return this way point after
                               //    combat.
    GenerateNPCTreasure();     //* Use this to create a small amount of treasure on the creature
    SetListenPattern(OBJECT_SELF, "**", 20600); //listen to all text
    SetLocalInt(OBJECT_SELF, "hls_Listening", 1); //listen to all text
    SetListening(OBJECT_SELF, TRUE);          //be sure NPC is listening
}

//::///////////////////////////////////////////////
//:: fb_guard_death -- OnDeath for the Kallrist Crypt guardian (the placed
//:: badass_2 "Fell Beast" instance). Replaces the shared demondeath on this
//:: instance so it can DROP the Horn of the Fell Beast without demondeath's
//:: destroy() wiping the corpse's inventory.
//::
//:: Behavior:
//::   1. Award "Horn of the Fell Beast" (horn_fellbeast / tag HornFellBeast)
//::      to the killer and to every PC party member present in the area,
//::      skipping anyone who already owns one (no farming duplicates).
//::      The Horn both summons the Fell Beast companion and unlocks the
//::      Kallrist Crypt forge.
//::   2. Preserve the boss behavior: feed the Roll of the Fallen respawn
//::      (SE_DoCreatureRespawn, gated exactly as demondeath does) and the
//::      fireball nova. Destroy only the wielded weapon -- never the corpse
//::      inventory.
//:://////////////////////////////////////////////
#include "NW_I0_SPELLS"
#include "se_respawn_inc"

const string HORN_RESREF = "horn_fellbeast";
const string HORN_TAG    = "HornFellBeast";

void GiveHorn(object oPC)
{
    if (!GetIsPC(oPC)) return;
    if (GetIsObjectValid(GetItemPossessedBy(oPC, HORN_TAG))) return; // already has one
    CreateItemOnObject(HORN_RESREF, oPC);
    FloatingTextStringOnCreature(
        "The Fell Beast falls -- and its horn is yours to sound.", oPC, FALSE);
}

void main()
{
    object oSelf = OBJECT_SELF;

    // --- Horn to the killer and their present party ---
    object oKiller = GetLastKiller();
    object oAnchor = GetIsPC(oKiller) ? oKiller
                                      : (GetIsPC(GetMaster(oKiller)) ? GetMaster(oKiller)
                                                                     : oKiller);
    if (GetIsObjectValid(oAnchor))
    {
        object oMember = GetFirstFactionMember(oAnchor, TRUE); // PCs only
        while (GetIsObjectValid(oMember))
        {
            if (GetArea(oMember) == GetArea(oSelf))
                GiveHorn(oMember);
            oMember = GetNextFactionMember(oAnchor, TRUE);
        }
    }

    // --- Boss upkeep: Roll of the Fallen respawn (same gate as demondeath) ---
    if (FindSubString(GetTag(oSelf), "NSP") == -1)
        SE_DoCreatureRespawn();

    // Destroy the wielded weapon (as demondeath did); leave the rest of the
    // corpse inventory intact so nothing swallows the Horn logic's assumptions.
    DestroyObject(GetItemInSlot(INVENTORY_SLOT_RIGHTHAND, oSelf));

    // --- Fireball nova ---
    location lTarget = GetLocation(oSelf);
    effect eExplode = EffectVisualEffect(VFX_FNF_FIREBALL);
    effect eVis = EffectVisualEffect(VFX_IMP_FLAME_M);
    ApplyEffectAtLocation(DURATION_TYPE_INSTANT, eExplode, lTarget);

    object oTarget = GetFirstObjectInShape(SHAPE_SPHERE, RADIUS_SIZE_HUGE,
        lTarget, TRUE, OBJECT_TYPE_CREATURE | OBJECT_TYPE_DOOR);
    while (GetIsObjectValid(oTarget))
    {
        SignalEvent(oTarget, EventSpellCastAt(oSelf, SPELL_FIREBALL));
        float fDelay = GetDistanceBetweenLocations(lTarget, GetLocation(oTarget)) / 20.0;
        if (!MyResistSpell(oSelf, oTarget, fDelay))
        {
            int nDamage = GetReflexAdjustedDamage(10, oTarget, GetSpellSaveDC(),
                                                  SAVING_THROW_TYPE_FIRE);
            if (nDamage > 0)
            {
                effect eDam = EffectDamage(nDamage, DAMAGE_TYPE_FIRE);
                DelayCommand(fDelay, ApplyEffectToObject(DURATION_TYPE_INSTANT, eDam, oTarget));
                DelayCommand(fDelay, ApplyEffectToObject(DURATION_TYPE_INSTANT, eVis, oTarget));
            }
        }
        oTarget = GetNextObjectInShape(SHAPE_SPHERE, RADIUS_SIZE_HUGE,
            lTarget, TRUE, OBJECT_TYPE_CREATURE | OBJECT_TYPE_DOOR);
    }
}

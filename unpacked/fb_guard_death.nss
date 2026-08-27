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

// Walk the full master chain (a summon of a henchman is two deep) and return
// the owning PC, or OBJECT_INVALID. Mirrors Bst_OwningPC in bst_ondeath.nss.
object FB_OwningPC(object o)
{
    while (GetIsObjectValid(GetMaster(o))) o = GetMaster(o);
    if (GetIsPC(o) && !GetIsDM(o)) return o;
    return OBJECT_INVALID;
}

void GiveHorn(object oPC)
{
    if (!GetIsPC(oPC) || GetIsDM(oPC)) return;
    if (GetIsObjectValid(GetItemPossessedBy(oPC, HORN_TAG))) return; // already has one

    object oNew = CreateItemOnObject(HORN_RESREF, oPC);
    if (!GetIsObjectValid(oNew))
    {
        SendMessageToPC(oPC, "The Horn of the Fell Beast could not be given. "
                           + "Tell an admin.");
        WriteTimestampedLogEntry("[FellBeast] Horn grant FAILED for "
                               + GetName(oPC) + " (" + GetPCPlayerName(oPC) + ")");
        return;
    }

    FloatingTextStringOnCreature(
        "The Fell Beast falls -- and its horn is yours to sound.", oPC, FALSE);

    // A full pack makes the engine drop the item at the PC's feet with no
    // message -- and this area's OnExit (cleanup.nss) destroys loose items when
    // the last PC leaves, so a silent drop is a lost Horn on a respawn-gated
    // boss. Same check as q_potd_reward.nss.
    if (!GetIsObjectValid(GetItemPossessedBy(oPC, HORN_TAG)))
        SendMessageToPC(oPC, "Your pack was full -- the Horn of the Fell Beast "
                           + "lies at your feet. Pick it up before you leave.");

    WriteTimestampedLogEntry("[FellBeast] Horn granted to " + GetName(oPC)
                           + " (" + GetPCPlayerName(oPC) + ")");
}

void main()
{
    object oSelf = OBJECT_SELF;

    // --- Horn to the killer and their present party ---
    // Two independent sources, unioned, because GiveHorn is idempotent per PC:
    //
    //  1. The killer's party. The old code walked only ONE GetMaster level and
    //     fell back to a NON-PC anchor, so a nested associate, a trap kill, an
    //     environmental kill or a DM kill left GetFirstFactionMember(oAnchor,
    //     TRUE) yielding nothing and NOBODY got a Horn -- silently, on a boss
    //     that is then respawn-gated for 15 minutes.
    //  2. The bestiary damage-contributor list. bst_ondamage.nss has already
    //     recorded every PC who hurt this creature, master-walked to the owning
    //     PC, in bst_ctrb_N. Nothing deletes those locals, and bst_ondeath.nss
    //     chains us last, so they are still here. This is the safety net for
    //     every killer-resolution case above.
    object oAnchor = FB_OwningPC(GetLastKiller());
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

    int nCtrb = GetLocalInt(oSelf, "bst_ctrb_n");
    int i;
    for (i = 0; i < nCtrb; i++)
    {
        object oC = GetLocalObject(oSelf, "bst_ctrb_" + IntToString(i));
        if (GetIsObjectValid(oC) && GetArea(oC) == GetArea(oSelf))
            GiveHorn(oC);
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

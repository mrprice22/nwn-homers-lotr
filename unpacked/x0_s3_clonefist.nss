//::///////////////////////////////////////////////
//:: x0_s3_clonefist
//:: MODULE OVERRIDE of the BioWare stock script (Copyright (c) 2001 Bioware Corp.)
//:://////////////////////////////////////////////
/*
    Create a fiery version of the character to help them fight.

    ## Why this file exists (it is not stock)

    The stock script builds the clone with CopyObject(oPC, ...), and CopyObject
    copies INVENTORY AND EQUIPMENT. For three rounds there is a creature standing
    next to the player wearing duplicates of the player's real gear -- and:

      * plot does NOT stop pickpocket, so the clone's pack can be robbed for real
        items, and
      * disarm_catch.nss only reconciles disarms where the VICTIM is a PC, so a
        disarmed clone drops a real weapon on the ground with nothing cleaning it
        up.

    Either one is a genuine item duplication. The stock script's own plot flag is
    applied on a 0.5s delay ("so items don't drop"), which is about the clone's
    corpse, not about theft, and leaves a window besides.

    Reached from item property "Flame twin" = iprp_spells row 442 (Twinfists) ->
    spells.2da row 615 -> ImpactScript x0_s3_clonefist. Verified from the module's
    own hak stack, not assumed. In this module the property is carried by item068
    ("Homer's Touch", cheat-chest only, can_chest tier) and flametwincloak.

    ## What changed, and nothing else

    Exactly one new call -- CloneFistHarden() -- immediately after the CopyObject,
    plus the matching cleanup on the expiry path. The fire VFX, the commoner
    faction, the master link, the 6-tick FakeHB timer, the goodbye fireball and the
    caster's 3.5s fire immunity are all stock and must stay that way.

    Rule this enforces, which is module-wide and not specific to this spell:
    ANY clone, copy or duplicate of a player must carry nothing real.
    See CLAUDE-gotchas.md.
*/
//:://////////////////////////////////////////////
#include "nw_i0_generic"

const string CLONEFIST_LOCKED = "X0_L_CLONEFIST_LOCKED";

// Destroy one item, clearing plot first -- plot items resist DestroyObject.
// Same defensive order as kalrist_gems.nss.
void CloneFistNuke(object oItem)
{
    if (!GetIsObjectValid(oItem)) return;
    SetPlotFlag(oItem, FALSE);
    DestroyObject(oItem);
}

// Make the clone safe to stand next to.
//
//   carried inventory -> destroyed outright. Nothing in the pack to pickpocket.
//   equipped slots    -> kept (the clone should still LOOK like the caster) but
//                        locked down: not droppable, not pickpocketable, plot.
//
// Known residual, deliberately recorded rather than papered over: disarm is an
// engine action and disarm_catch.nss does not cover NPC victims, so a disarmed
// clone could still put a weapon on the ground. CloneFistStrip() on the expiry
// path bounds that to the clone's ~3 round life. Closing it fully means teaching
// disarm_catch about NPC victims, which is a separate change.
void CloneFistHarden(object oClone)
{
    if (!GetIsObjectValid(oClone)) return;

    object oItem = GetFirstItemInInventory(oClone);
    while (GetIsObjectValid(oItem))
    {
        object oNext = GetNextItemInInventory(oClone);   // step before destroying
        CloneFistNuke(oItem);
        oItem = oNext;
    }

    int nSlot;
    for (nSlot = 0; nSlot <= INVENTORY_SLOT_CARMOUR; nSlot++)
    {
        oItem = GetItemInSlot(nSlot, oClone);
        if (!GetIsObjectValid(oItem)) continue;
        SetDroppableFlag(oItem, FALSE);
        SetPickpocketableFlag(oItem, FALSE);
        SetPlotFlag(oItem, TRUE);
    }

    SetLocalInt(oClone, CLONEFIST_LOCKED, TRUE);
}

// Take the equipped copies with the clone when it goes.
void CloneFistStrip(object oClone)
{
    if (!GetIsObjectValid(oClone)) return;

    int nSlot;
    for (nSlot = 0; nSlot <= INVENTORY_SLOT_CARMOUR; nSlot++)
        CloneFistNuke(GetItemInSlot(nSlot, oClone));

    object oItem = GetFirstItemInInventory(oClone);
    while (GetIsObjectValid(oItem))
    {
        object oNext = GetNextItemInInventory(oClone);
        CloneFistNuke(oItem);
        oItem = oNext;
    }
}

void FakeHB()
{
    effect eFlame = EffectVisualEffect(VFX_IMP_FLAME_M);
    ApplyEffectToObject(DURATION_TYPE_INSTANT, eFlame, OBJECT_SELF);
    int nExplode = GetLocalInt(OBJECT_SELF, "X0_L_MYTIMERTOEXPLODE");
    object oMaster = GetLocalObject(OBJECT_SELF, "X0_L_MYMASTER");
    if (nExplode == 6)
    {

        ClearAllActions();
        PlayVoiceChat(VOICE_CHAT_GOODBYE);
        effect eFirePro = EffectDamageImmunityIncrease(DAMAGE_TYPE_FIRE, 100);
        ApplyEffectToObject(DURATION_TYPE_TEMPORARY, eFirePro, oMaster, 3.5);
        ActionCastSpellAtLocation(SPELL_FIREBALL, GetLocation(OBJECT_SELF), METAMAGIC_ANY, TRUE, PROJECTILE_PATH_TYPE_DEFAULT, TRUE);

        // OVERRIDE: the gear copies die with the clone. Ahead of the 0.5s
        // DestroyObject below so nothing survives the creature.
        CloneFistStrip(OBJECT_SELF);

        DestroyObject(OBJECT_SELF, 0.5);
        SetCommandable(FALSE);
        return;
    }
    else
    {
        object oEnemy = GetNearestCreature(CREATURE_TYPE_REPUTATION, REPUTATION_TYPE_ENEMY, oMaster, 1, CREATURE_TYPE_PERCEPTION, PERCEPTION_SEEN);
        // * attack my master's enemy
        if (GetIsObjectValid(oEnemy) )
        {
            DetermineCombatRound(oEnemy);
        }

        ActionMoveToObject(GetLocalObject(OBJECT_SELF, "X0_L_MYMASTER"), TRUE);
        SetLocalInt(OBJECT_SELF, "X0_L_MYTIMERTOEXPLODE", nExplode + 1);
        DelayCommand(3.0, FakeHB());
    }
}

void main()
{
    object oPC = OBJECT_SELF;
    object oFireGuy = CopyObject(oPC, GetLocation(OBJECT_SELF), OBJECT_INVALID, GetName(oPC) + "CLONEFROMFISTS");

    // OVERRIDE: before anything else can interact with it. Synchronous on
    // purpose -- a DelayCommand here would leave exactly the theft window this
    // file exists to close.
    CloneFistHarden(oFireGuy);

    SetLocalInt(oFireGuy, "X0_L_MYTIMERTOEXPLODE",1);
    SetLocalObject(oFireGuy, "X0_L_MYMASTER", oPC);
    ChangeToStandardFaction(oFireGuy, STANDARD_FACTION_COMMONER);
    SetPCLike(oPC, oFireGuy);
    DelayCommand(0.5, SetPlotFlag(oFireGuy, TRUE)); // * so items don't drop, I can destroy myself.
    AssignCommand(oFireGuy, FakeHB());
    effect eVis = EffectVisualEffect(VFX_DUR_ELEMENTAL_SHIELD);
    ApplyEffectToObject(DURATION_TYPE_PERMANENT, eVis, oFireGuy);

}

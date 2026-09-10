// cp_gloves -- Crash Party: Gloves of a Great Many Punches. Wave 3. ON-HIT item.
//
// The only item in the set that fires during COMBAT rather than on activation,
// which is why it is worth having at all -- everything else is something you
// stop and do.
//
// ## How it is reached, without a single line of dispatcher glue
//
// The gloves carry item property OnHitCastSpell -> ONHIT_UniquePower
// (iprp_onhitspell row 125 -> spells.2da 700 -> ImpactScript X2_S3_OnHitCast).
// That stock script already runs the item's TAG as a script when the module's
// tag-based scripting switch is on, and onmoduleload.nss turns it on. Tag ==
// ResRef == this file, so the chain completes with nothing overridden and no
// shared file touched.
//
// This script is therefore entered from three directions and has to tell them
// apart: an on-hit proc, and the equip/unequip pair (cp_equip.nss dispatches any
// cp_ item, and gloves are equippable).
//
// ## The BioWare performance warning is real, and is handled here
//
// x2_s3_onhitcast's own header says the property "can be a major performance hog
// when used extensively in a multi player module. Especially in higher levels,
// with each player having multiple attacks." At level 60 with four-plus attacks
// a round, this script runs several times per round per wearer.
//
// So the NON-PROC PATH IS THE HOT PATH and is kept to two reads and a die roll:
// event number, random, return. Nothing is looked up, no item is searched for,
// no string is built unless the proc actually fires. Do not add work above the
// roll.

#include "cp_inc"
#include "x2_inc_switches"

const int CP_PUNCH_CHANCE = 20;   // percent of hits that do anything at all

void main()
{
    object oPC = OBJECT_SELF;

    // --- equip / unequip: flavour only, never a charge -------------------
    if (GetLocalInt(oPC, "cp_worn_on"))
    {
        SendMessageToPC(oPC, "You pull on the gloves. Your knuckles feel lucky.");
        return;
    }
    if (GetUserDefinedItemEventNumber() != X2_ITEM_EVENT_ONHITCAST)
    {
        // Unequip, or any other path that is not a punch.
        return;
    }

    // --- HOT PATH: several times a round, per wearer ---------------------
    if (Random(100) >= CP_PUNCH_CHANCE) return;

    object oTarget = GetSpellTargetObject();
    if (!GetIsObjectValid(oTarget)) return;

    object oItem = CP_FindItem(oPC, "cp_gloves");
    if (!GetIsObjectValid(oItem)) return;

    if (!CP_ConsumeUse(oItem, CP_ItemCharges(9),
            "The gloves finally give out, seams bursting, and slide off your hands."))
        return;

    // Every row is cosmetic. Nothing here disables, damages or debuffs: an
    // on-hit item that could stun would be a pocket crowd-control device with
    // hundreds of charges, which is the trap Puppet Strings was restricted for.
    int nVfx = VFX_COM_HIT_SONIC;
    string sMsg = "lands one!";
    switch (Random(20))
    {
        case  0: nVfx = VFX_IMP_HEAD_SONIC;    sMsg = "rings like a gong!"; break;
        case  1: nVfx = VFX_COM_HIT_ELECTRICAL;sMsg = "gets a static shock!"; break;
        case  2: nVfx = VFX_IMP_PULSE_HOLY;    sMsg = "is briefly sanctified!"; break;
        case  3: nVfx = VFX_IMP_MAGBLUE;       sMsg = "sees stars!"; break;
        case  4: nVfx = VFX_COM_HIT_FIRE;      sMsg = "is singed!"; break;
        case  5: nVfx = VFX_COM_HIT_FROST;     sMsg = "gets a chill!"; break;
        case  6: nVfx = VFX_IMP_HEAD_ODD;      sMsg = "looks deeply confused!"; break;
        case  7: nVfx = VFX_IMP_HEALING_S;     sMsg = "is punched better!"; break;
        case  8: nVfx = VFX_COM_BLOOD_SPARK_LARGE; sMsg = "takes a proper wallop!"; break;
        case  9: nVfx = VFX_IMP_DUST_EXPLOSION;sMsg = "vanishes in a puff of dust!"; break;
        case 10: nVfx = VFX_IMP_SILENCE;       sMsg = "is left speechless!"; break;
        case 11: nVfx = VFX_IMP_HEAD_MIND;     sMsg = "has second thoughts!"; break;
        case 12: nVfx = VFX_COM_HIT_ACID;      sMsg = "is thoroughly pickled!"; break;
        case 13: nVfx = VFX_IMP_KNOCK;         sMsg = "hears a distant door open!"; break;
        case 14: nVfx = VFX_IMP_GREASE;        sMsg = "slips on absolutely nothing!"; break;
        case 15: nVfx = VFX_IMP_HEAD_HOLY;     sMsg = "has a religious experience!"; break;
        case 16: nVfx = VFX_IMP_LIGHTNING_M;   sMsg = "is briefly electrified!"; break;
        case 17: nVfx = VFX_IMP_FLAME_S;       sMsg = "smoulders gently!"; break;
        case 18: nVfx = VFX_IMP_FROST_S;       sMsg = "frosts over!"; break;
    }

    ApplyEffectToObject(DURATION_TYPE_INSTANT, EffectVisualEffect(nVfx), oTarget);
    FloatingTextStringOnCreature(GetName(oTarget) + " " + sMsg, oPC, FALSE);
}

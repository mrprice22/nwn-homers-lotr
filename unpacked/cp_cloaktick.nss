// cp_cloaktick -- Crash Party: the Cloak of a Thousand Faces' reroll chain.
//
// Stops the moment CP_CLOAK_ON goes away, so taking the cloak off ends it within
// one tick and cp_cloak.nss puts the wearer's real face back.
//
// One chain per wearer, guarded on a TIMESTAMP rather than a flag: creature
// locals are saved into the .bic and a flag stranded TRUE by a restart would
// stop the cloak working for good, whereas a stale timestamp just falls into the
// past and the next equip restarts it.

#include "cp_inc"

const string CP_CLOAK_ON   = "CP_CLOAK_ON";
const string CP_CLOAK_NEXT = "CP_CLOAK_NEXT";

int CP_CloakFace()
{
    switch (Random(12))
    {
        case  0: return APPEARANCE_TYPE_BADGER;
        case  1: return APPEARANCE_TYPE_CHICKEN;
        case  2: return APPEARANCE_TYPE_COW;
        case  3: return APPEARANCE_TYPE_PENGUIN;
        case  4: return APPEARANCE_TYPE_GOBLIN_A;
        case  5: return APPEARANCE_TYPE_KOBOLD_A;
        case  6: return APPEARANCE_TYPE_ORC_A;
        case  7: return APPEARANCE_TYPE_TROLL;
        case  8: return APPEARANCE_TYPE_OGRE;
        case  9: return APPEARANCE_TYPE_RAT;
        case 10: return APPEARANCE_TYPE_DWARF_NPC_MALE;
    }
    return APPEARANCE_TYPE_HALFLING_NPC_MALE;
}

void main()
{
    object oPC = OBJECT_SELF;
    if (!GetIsPC(oPC)) return;
    if (!GetLocalInt(oPC, CP_CLOAK_ON)) { DeleteLocalInt(oPC, CP_CLOAK_NEXT); return; }

    ApplyEffectToObject(DURATION_TYPE_INSTANT,
        EffectVisualEffect(VFX_IMP_POLYMORPH), oPC);
    SetCreatureAppearanceType(oPC, CP_CloakFace());

    int nDelay = Random(20) + 25;
    SetLocalInt(oPC, CP_CLOAK_NEXT, CP_Now() + nDelay + 5);
    DelayCommand(IntToFloat(nDelay), ExecuteScript("cp_cloaktick", oPC));
}

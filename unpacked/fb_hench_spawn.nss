//::///////////////////////////////////////////////
//:: fb_hench_spawn -- OnSpawn for the SUMMONED Fell Beast companion
//:: (blueprint fellbeast_h, called from horn_summon via CreateObject).
//::
//:: Unlike the crypt guardian's spawn_fellbeast, this must NOT:
//::   * leash the creature to its spawn area (a henchman follows the PC
//::     across areas) -- so it sets NO_LEASH=1 first (see leash_to_area.nss),
//::   * install the bestiary boss wrappers, generate treasure, or register
//::     as anything trackable.
//:: It keeps the fell-beast look (the two durational auras) and the stock
//:: generic setup so standard associate AI (hench_demon_hb -> nw_ch_ac1)
//:: behaves normally.
//:://////////////////////////////////////////////
#include "NW_I0_GENERIC"

void main()
{
    // Companion, not a leashed guardian: exempt from the area anti-kite leash.
    SetLocalInt(OBJECT_SELF, "NO_LEASH", 1);

    // Fell-beast aura, same as the guardian's spawn.
    ApplyEffectToObject(DURATION_TYPE_PERMANENT,
        EffectVisualEffect(VFX_DUR_PROT_SHADOW_ARMOR), OBJECT_SELF);
    ApplyEffectToObject(DURATION_TYPE_PERMANENT,
        EffectVisualEffect(VFX_DUR_GLOW_BROWN), OBJECT_SELF);

    // Standard generic behavior so the associate AI runs cleanly.
    SetListeningPatterns();
    WalkWayPoints();
}

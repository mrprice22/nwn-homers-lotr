// orb_lvldrain.nss - "Orb of Level Drain" (tag OrbLevelDrain), an admin test
// tool. Dispatched by tag from dmfi_activate.nss.
//
// WHY IT EXISTS. Energy drain is the case the Legendary Feats revoke path must
// NOT get wrong: a drained level-60 character still holds its class levels, so
// its picks must survive, while a REAL drop below 60 (death XP loss, a relevel)
// must take them away. LegFeat_EnsureAllotment returns early whenever
// LegFeat_HasNegativeLevels() is true - and nothing in the module could produce
// negative levels on demand to prove it in game. This orb can.
//
// One button, two directions: activate to take 5 negative levels, activate
// again to clear them. The effect is SUPERNATURAL and PERMANENT on purpose -
// that is what an enemy's level drain is, so this reproduces the real thing
// rather than an imitation of it: it survives rest and dispel, it sticks to the
// character across a logout, and a Restoration removes it (see
// rm_healingscript.nss). That makes the relog half of the check direct - drain,
// log out, log back in, and the drain AND the picks should both still be there.
//
// The clear branch therefore cannot rely on the effect tag: the drain outliving
// the session is the point, and nothing guarantees the tag comes back with it.
// So it clears tagged effects first, and falls back to clearing every negative
// level on the character, saying which it did.
//
// Admin-gated (can_admin). The orb lies on the floor of Castle Homeless next to
// WP_Homeless; a player who somehow got hold of one gets a refusal, not levels.

#include "admin_db"

const string ORB_EFFECT_TAG = "ORB_LVLDRAIN";
const int    ORB_LEVELS     = 5;

// Negative levels on the character, ours (tagged) counted separately from any
// the character picked up the hard way.
int Orb_CountDrain(object oPC, int bTaggedOnly)
{
    int nCount = 0;
    effect e = GetFirstEffect(oPC);
    while (GetIsEffectValid(e))
    {
        if (bTaggedOnly)
        {
            if (GetEffectTag(e) == ORB_EFFECT_TAG) nCount++;
        }
        else if (GetEffectType(e) == EFFECT_TYPE_NEGATIVELEVEL) nCount++;
        e = GetNextEffect(oPC);
    }
    return nCount;
}

// Returns the number removed. Tagged first; the untagged sweep is the fallback
// for a drain that came back from a logout without its tag.
int Orb_ClearDrain(object oPC, int bTaggedOnly)
{
    int nRemoved = 0;
    effect e = GetFirstEffect(oPC);
    while (GetIsEffectValid(e))
    {
        if (bTaggedOnly ? (GetEffectTag(e) == ORB_EFFECT_TAG)
                        : (GetEffectType(e) == EFFECT_TYPE_NEGATIVELEVEL))
        {
            RemoveEffect(oPC, e);
            nRemoved++;
        }
        e = GetNextEffect(oPC);
    }
    return nRemoved;
}

// Class levels, which no effect can touch - the same measure legfeat_inc's
// LegFeat_TrueLevel uses. Printed next to GetHitDice() so the readout shows
// the two diverging, which is the whole point of the drain.
int Orb_ClassLevels(object oPC)
{
    return GetLevelByPosition(1, oPC) + GetLevelByPosition(2, oPC)
         + GetLevelByPosition(3, oPC) + GetLevelByPosition(4, oPC);
}

void main()
{
    object oPC = OBJECT_SELF;
    if (!GetIsPC(oPC)) return;

    if (!Admin_CanAdmin(oPC))
    {
        SendMessageToPC(oPC, "The orb is cold and inert in your hand. Nothing happens.");
        return;
    }

    if (Orb_CountDrain(oPC, FALSE) > 0)
    {
        // Ours by tag if the tag is still there; otherwise every negative level
        // on the character - after a logout that is the only handle left, and an
        // admin holding this orb wants it to undo itself either way.
        int bTagged  = Orb_CountDrain(oPC, TRUE) > 0;
        int nRemoved = Orb_ClearDrain(oPC, bTagged);
        ApplyEffectToObject(DURATION_TYPE_INSTANT,
                            EffectVisualEffect(VFX_IMP_RESTORATION_GREATER), oPC);
        SendMessageToPC(oPC, "The orb releases you: " + IntToString(nRemoved)
                             + (bTagged ? " of its own negative level effects cleared."
                                        : " negative level effect(s) cleared"
                                          + " - untagged, so ANY drain you were"
                                          + " carrying went with them."));
    }
    else
    {
        effect eDrain = SupernaturalEffect(TagEffect(EffectNegativeLevel(ORB_LEVELS),
                                                     ORB_EFFECT_TAG));
        ApplyEffectToObject(DURATION_TYPE_PERMANENT, eDrain, oPC);
        ApplyEffectToObject(DURATION_TYPE_INSTANT,
                            EffectVisualEffect(VFX_IMP_NEGATIVE_ENERGY), oPC);
        SendMessageToPC(oPC, "The orb drinks. You take " + IntToString(ORB_LEVELS)
                             + " negative levels - activate it again to clear them.");
    }

    // The readout is the test: class levels must not move, effective level must.
    SendMessageToPC(oPC, "  class levels: " + IntToString(Orb_ClassLevels(oPC))
                       + "   GetHitDice: " + IntToString(GetHitDice(oPC))
                       + "   negative level effects: "
                       + IntToString(Orb_CountDrain(oPC, FALSE)));
}

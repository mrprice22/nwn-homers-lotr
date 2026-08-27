//::///////////////////////////////////////////////
//:: fb_horn_fix -- one-time migration of the Horn of the Fell Beast
//::
//:: The Horn shipped as BaseItem 52 (a RING, cloned from mw_mixtape). Two
//:: consequences: it rendered as a 1x1 ring icon shared with three other rings
//:: in the pack -- players could not find it -- and NWN only fires an
//:: EQUIPPABLE item's "Cast Spell: Unique Power" while the item is worn, so
//:: following the Horn's own description ("keep it in your pack") guaranteed it
//:: did nothing. The blueprint is now BaseItem 29 (miscmedium, non-equippable,
//:: activatable straight from the pack, icon iit_midmisc_182 -- a blackened
//:: curved horn).
//::
//:: A blueprint is only read when an item is created FRESH, so every Horn
//:: already minted into a .bic keeps the old base item forever. This swaps it,
//:: from mod_cliententer. Idempotent -- a converted Horn is a no-op on every
//:: later login.
//:://////////////////////////////////////////////

const string HORN_RESREF = "horn_fellbeast";
const string HORN_TAG    = "HornFellBeast";

void main()
{
    object oPC = OBJECT_SELF;
    if (!GetIsPC(oPC)) return;

    // GetItemPossessedBy matches on TAG and sees equipped items too, which
    // matters here: a player who worked out the ring had to be worn will have
    // it in a ring slot rather than the backpack.
    object oOld = GetItemPossessedBy(oPC, HORN_TAG);
    if (!GetIsObjectValid(oOld)) return;
    if (GetBaseItemType(oOld) == BASE_ITEM_MISCMEDIUM) return;  // already converted

    object oNew = CreateItemOnObject(HORN_RESREF, oPC);
    if (!GetIsObjectValid(oNew))
    {
        // Do NOT destroy the old one -- leaving the player a broken Horn beats
        // leaving them none. Retry on the next login.
        SendMessageToPC(oPC, "Your pack was too full to reforge the Horn of the "
                           + "Fell Beast. Make room and log in again.");
        return;
    }

    DestroyObject(oOld);
    SendMessageToPC(oPC, "The Horn of the Fell Beast has taken its true shape -- "
                       + "sound it from your pack.");
    WriteTimestampedLogEntry("[FellBeast] Horn converted ring->miscmedium for "
                           + GetName(oPC) + " (" + GetPCPlayerName(oPC) + ")");
}

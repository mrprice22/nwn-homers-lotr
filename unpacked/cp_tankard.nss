// cp_tankard -- Crash Party: the Magical Tankard. The event's mascot item.
//
// Dispatched by tag from dmfi_activate.nss (Mod_OnActvtItem), so OBJECT_SELF is
// the activating PC.
//
// Take a sip and you belch, stagger and fall over -- and keep doing it at random
// for the next few minutes. Every sip stacks "tipsiness", which makes the fits
// come more often and last longer, up to a cap.
//
// Purely cosmetic ON PURPOSE. This uses ActionPlayAnimation, never
// EffectKnockdown: a real knockdown is a combat effect, so it could interrupt a
// fight or be used to grief someone, and the whole point of the item is that it
// is funny rather than disruptive.
//
// No CP_IsOn() check -- see cp_inc.nss. The tankard keeps working long after the
// party is over, which is the promise made to players.

#include "cp_inc"

const int    CP_TIPSY_CAP  = 10;
const string CP_TIPSY_VAR  = "CP_TIPSY";
const string CP_TIPSY_END  = "CP_TIPSY_UNTIL";
const string CP_TIPSY_NEXT = "CP_TIPSY_NEXT";

void main()
{
    object oPC = OBJECT_SELF;
    if (!GetIsPC(oPC)) return;

    // A short guard so a held-down hotkey cannot burn the charges or spam the
    // area with sound. Same convention as the emote scripts' "Dancefix".
    if (CP_Spam(oPC, "cp_sip_cd", 4.0)) return;

    object oItem = CP_FindItem(oPC, "cp_tankard");
    if (!GetIsObjectValid(oItem)) return;

    if (!CP_ConsumeUse(oItem, CP_ItemCharges(0),
            "Your tankard drains to the dregs, cracks down the side and falls to pieces."))
        return;

    // Tipsiness: stacks per sip, capped, and decays only by wearing off.
    int nTipsy = GetLocalInt(oPC, CP_TIPSY_VAR) + 1;
    if (nTipsy > CP_TIPSY_CAP) nTipsy = CP_TIPSY_CAP;
    SetLocalInt(oPC, CP_TIPSY_VAR, nTipsy);

    int nTotal = CP_AddSips(oPC, 1);

    // Fits run for 2 + tipsiness minutes from the LAST sip, so drinking again
    // extends the bender rather than restarting a shorter one.
    int nUntil = CP_Now() + (2 + nTipsy) * 60;
    SetLocalInt(oPC, CP_TIPSY_END, nUntil);

    string sMsg = "You take a long pull from the tankard.";
    if (nTipsy >= 8)      sMsg = "You take another pull. The room is definitely moving.";
    else if (nTipsy >= 5) sMsg = "You take another pull. Everything is much funnier now.";
    else if (nTipsy >= 3) sMsg = "You take another pull. You feel wonderfully warm.";
    SendMessageToPC(oPC, sMsg + " (" + IntToString(nTotal) + " sips)");

    AssignCommand(oPC, ActionPlayAnimation(ANIMATION_FIREFORGET_DRINK, 1.0));
    AssignCommand(oPC, PlaySound(CP_BelchSound(nTipsy)));

    // EXACTLY ONE after-effects chain per drinker, ever.
    //
    // cp_tipsy tail-schedules itself, so kicking it off here on every sip would
    // start a SECOND chain on the second drink, a third on the third, and so on
    // -- belches multiplying geometrically with every mouthful. That is the same
    // runaway shape the event deliberately designed out of its items, and it
    // does not get a pass here.
    //
    // CP_TIPSY_NEXT is when the live chain's next tick is due. A pending tick
    // means a chain already owns this PC, so we leave it alone and only extend
    // the deadline above. It is a TIME rather than a boolean flag on purpose:
    // creature locals are serialised into the .bic, so a flag left set by a
    // server restart would lock the chain off permanently, whereas a stale
    // timestamp simply falls into the past and the next sip restarts it.
    if (CP_Now() >= GetLocalInt(oPC, CP_TIPSY_NEXT))
    {
        int nDelay = Random(10) + 8;
        SetLocalInt(oPC, CP_TIPSY_NEXT, CP_Now() + nDelay + 5);   // slack for lag
        DelayCommand(IntToFloat(nDelay), ExecuteScript("cp_tipsy", oPC));
    }
}

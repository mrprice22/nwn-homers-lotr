// csp_evt.nss - NUI event handler for the caster spell picker.
// Registered per-window via the sEventScript arg of NuiCreate in csp_nui.

#include "csp_nui"

void main()
{
    if (NuiGetEventType() != "click") return;   // buttons send "click"

    object oPC   = NuiGetEventPlayer();
    string sElem = NuiGetEventElement();

    if (sElem == "bclose")
    {
        CSP_Close(oPC);
        return;
    }

    // "l<n>" - show spell level n. Stored +1 so level 0 is not "unset".
    if (GetStringLeft(sElem, 1) == "l")
    {
        int nLvl = StringToInt(GetSubString(sElem, 1, GetStringLength(sElem) - 1));
        if (nLvl < 0 || nLvl > 9) return;
        SetLocalInt(oPC, CSP_SEL, nLvl + 1);
        CSP_Open(oPC);
        return;
    }

    // "i<spellid>" - show that spell in the detail pane. Rebuilding the window
    // is how the pane updates, same as the level tabs above.
    if (GetStringLeft(sElem, 1) == "i")
    {
        SetLocalInt(oPC, CSP_DTL,
            StringToInt(GetSubString(sElem, 1, GetStringLength(sElem) - 1)) + 1);
        CSP_Open(oPC);
        return;
    }

    // "s<spellid>" - learn that spell.
    if (GetStringLeft(sElem, 1) != "s") return;
    int nSpellId = StringToInt(GetSubString(sElem, 1, GetStringLength(sElem) - 1));

    int nResult = CSP_Learn(oPC, nSpellId);

    switch (nResult)
    {
        case CSP_OK:
            SendMessageToPC(oPC, "Spell added to your spellbook: "
                + CSP_SpellName(nSpellId) + ".");
            break;

        case CSP_NOPICKS:
            SendMessageToPC(oPC, "You have no spell picks remaining.");
            break;

        case CSP_KNOWN:
            SendMessageToPC(oPC, "You already know that spell.");
            break;

        // Charged but not granted. This should be unreachable - it means the
        // server accepted the pick and the engine then refused to write the
        // spell - so say so plainly rather than leaving the player to notice a
        // missing spell later.
        case CSP_FAILED:
            SendMessageToPC(oPC, "The server could not add " + CSP_SpellName(nSpellId)
                + " to your spellbook. Please report this to an administrator.");
            break;

        default:
            SendMessageToPC(oPC, "You cannot learn that spell.");
            break;
    }

    // Rebuild either way: the learned spell leaves the list and the header
    // count drops. Closing outright on the last pick would hide the result.
    CSP_Open(oPC);
}

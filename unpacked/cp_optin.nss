// cp_optin -- penguin conversation action: claim this account's party-crasher
// slot for the speaking character, then hand over everything released so far.
#include "cp_inc"

void main()
{
    object oPC = GetPCSpeaker();
    if (!GetIsObjectValid(oPC) || !GetIsPC(oPC)) return;

    // Re-verify at grant time rather than trusting the conditional that showed
    // this reply: between the menu rendering and the click, another character on
    // the same account could have taken the slot. Same reasoning as the
    // reward-and-take rule in CLAUDE-nwscript.md.
    // reward-exploit-ok: nothing is consumed here; the guard is the slot itself
    if (CP_HasCrasher(oPC))
    {
        if (!CP_IsCrasher(oPC))
        {
            SendMessageToPC(oPC, "Too late - another of your characters just signed up.");
            return;
        }
    }
    else
    {
        CP_OptIn(oPC);
    }

    SendMessageToPC(oPC,
        "You are this account's party crasher. Come back and say you are out if "
        + "you would rather one of your other characters carried the tankard.");

    CP_GrantUpToWave(oPC);
}

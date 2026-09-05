// merit_graf_prep.nss - build the "is this the one?" prompt (token 5039) from
// whatever the player currently has selected on the easel.
#include "merit_redeem"
#include "graf_db"
void main()
{
    object oPC = GetPCSpeaker();
    Graf_InitDb();

    struct graf_pick p = Graf_GetPick(oPC);
    SetLocalInt(oPC, "merit_graf_ok", FALSE);

    if (p.appearance <= 0)
    {
        SetCustomToken(5039, "You've not settled on anything yet. The mason's "
            + "plinth stands over there - work the stone until it looks right, "
            + "then come back and I'll write it down.");
        return;
    }

    string s = "So: " + p.app_name + " (" + p.category + ")";
    if (p.name != "")  s += ", named '" + p.name + "'";
    if (p.descr != "") s += ", reading '" + p.descr + "'";
    s += ". Shall I put that down for the DM?";
    SetCustomToken(5039, s);
    SetLocalInt(oPC, "merit_graf_ok", TRUE);
}

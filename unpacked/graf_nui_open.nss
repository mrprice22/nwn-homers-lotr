// graf_nui_open.nss - open the name/description form. Reached from the easel
// conversation (an ending node, so the dialogue window is out of the way).
#include "graf_nui_inc"
void main()
{
    object oPC = GetPCSpeaker();
    if (!GetIsObjectValid(oPC)) oPC = OBJECT_SELF;
    if (!GetIsPC(oPC)) return;

    Graf_InitDb();
    int nOld = NuiFindWindow(oPC, GRAF_NUI_ID);
    if (nOld) NuiDestroy(oPC, nOld);

    int nTok = NuiCreate(oPC, Graf_NuiWindow(oPC), GRAF_NUI_ID, "graf_nui_evt");
    SetLocalInt(oPC, GRAF_NUI_TOK, nTok);

    struct graf_pick p = Graf_GetPick(oPC);
    NuiSetBind(oPC, nTok, "gname",  JsonString(p.name));
    NuiSetBind(oPC, nTok, "gdescr", JsonString(p.descr));
    NuiSetBind(oPC, nTok, "gstat",  JsonString("Write it, then Save."));
}

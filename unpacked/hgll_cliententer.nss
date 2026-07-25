// hgll_cliententer — LEGACY HGLL login residue. NOT an event handler any more.
//
// The module's Mod_OnClientEntr hook is mod_cliententer.nss; the general login
// wiring moved there (roadmap: ll-hgll-split-cliententer). All that is left
// here is the one genuinely legendary-leveler-specific step: clearing the
// queued Letoscript string the retired NWNX2 HGLL port left on pre-port
// characters (the plugin used to replay it on next login; NWNX:EE never did).
//
// Called once, as ExecuteScript("hgll_cliententer", oPC) from mod_cliententer,
// so OBJECT_SELF is the logging-in PC. Delete this file and that one call
// together when the leveler goes (roadmap: ll-hgll-remove-scripts).

void main()
{
    object oPC = OBJECT_SELF;
    SetLocalString(oPC, "LetoScript", "");
    SetLocalString(oPC, "LetoscriptLL", "");
}

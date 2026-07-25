// hgll_client_exit — LEGACY HGLL logout residue. NOT an event handler any more.
//
// The module's Mod_OnClientLeav hook is mod_clientexit.nss; the general logout
// wiring (epic summons, bank boxes, persistent-state snapshot, BIC export)
// moved there (roadmap: ll-hgll-split-cliententer). All that is left here is
// the legendary-leveler step: a level-up interrupted by a logout leaves its
// staged picks on the PC, and PC locals ride into the BIC, so they are dropped
// before the export. tests/check_hgll_transactional.py guards that.
//
// Called once, as ExecuteScript("hgll_client_exit", PC) from mod_clientexit —
// ahead of ExportSingleCharacter — so OBJECT_SELF is the leaving PC. Delete
// this file and that one call together when the leveler goes (roadmap:
// ll-hgll-remove-scripts).

#include "hgll_func_inc"

void main()
{
    object PC = OBJECT_SELF;
    HGLL_ClearPendingPicks(PC);
    SetLocalString(PC, "LetoScript", "");
}

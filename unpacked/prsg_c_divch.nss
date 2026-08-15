// prsg_c_divch.nss - hub line gate for the Divine Champions
// (roadmap: prestige-trainer-hub). Shows Halmir's branch for this order
// only when the PC meets the order's minimum level (see prsg_inc.nss).
#include "qline_gate_inc"
#include "prsg_inc"

int StartingConditional()
{
    // Prestige orders pulled back 2026-08-14 for creative rework; the
    // branch stays wired but never shows. See qline_gate_inc.nss.
    if (QL_LineOff("prsg")) return FALSE;

    return PRSG_MeetsLevel(GetPCSpeaker(), PRSG_LVL_DIVCH);
}

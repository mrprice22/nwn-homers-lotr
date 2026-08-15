// prsg_c_off.nss - shows a prestige-order branch on Halmir's root only while
// the prestige-order trials are live (roadmap: prestige-quests).
//
// The orders were pulled back 2026-08-14 for creative rework, so this currently
// returns FALSE everywhere. Used on the "Which of the old orders would hear my
// name as I stand?" summary reply, which the twelve per-order conditionals
// (prsg_c_harper and friends) do not cover. See qline_gate_inc.nss.
#include "qline_gate_inc"

int StartingConditional()
{
    return !QL_LineOff("prsg");
}

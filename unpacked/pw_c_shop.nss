// pw_c_shop.nss - StartingConditional on Odo Proudfoot's leaf-counter reply.
// (roadmap: concerning-pipeweed)
//
// Odo only keeps a counter for someone who has settled his genealogy dispute
// and WON it. The win is stamped in questcddb under "concern_hob_won" by
// Concerning Hobbits; the existing "concern_hob" key is stamped win or lose
// and so cannot serve as the gate.
//
// NOTE: Concerning Hobbits does not stamp "concern_hob_won" yet -- that piece
// has not shipped. Until it does, QCD_LastStamp returns 0 for everybody and
// the leaf branch simply never appears. That is the correct closed state, not
// a bug: it no-ops gracefully and starts working the moment the key is written.

#include "quest_cd_inc"

int StartingConditional()
{
    object oPC = GetPCSpeaker();
    if (!GetIsPC(oPC)) return FALSE;
    return QCD_LastStamp(oPC, "concern_hob_won") > 0;
}

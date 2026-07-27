// nextlvl_evt.nss -- NWNX_ON_LEVEL_UP_AFTER / NWNX_ON_LEVEL_DOWN_AFTER handler
// for the "Next Level" character-sheet fix. Subscribed in onmoduleload.nss.
//
// The TLK override is per player and carries a level-specific number, so it has
// to be recomputed every time the level moves. Login is covered by
// mod_cliententer.nss; this covers levelling in both directions (death XP loss
// can drain a level back below 40, which must restore the stock string).
//
// See nextlvl_inc.nss for why the override exists at all.

#include "nextlvl_inc"

void main()
{
    NextLevel_FixTlk(OBJECT_SELF);
}

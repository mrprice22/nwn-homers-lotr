// Ammo menu slot 7 picked: replicate that ammunition and burn one use of the
// quiver. All the work is in AmmoRep_Pick (ammorep_inc.nss).
#include "ammorep_inc"

void main()
{
    AmmoRep_Pick(GetPCSpeaker(), 7);
}

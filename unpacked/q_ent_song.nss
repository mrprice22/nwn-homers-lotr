// The Thirteenth Ent (roadmap: thirteenth-ent)
// Bard Song listener. Executed from nw_s2_bardsong.nss (this module's own
// Bard Song override, the real ImpactScript of the Bard Song feat) on every
// use of the feat, so the song's own behaviour is untouched. Does nothing
// unless the singer is mid-concert in front of Leaflock.
#include "q_ent_inc"

void main()
{
    ENT_OnBardSong();
}

// staticspawndol -- OnDeath for a rally-shout guardian.
//
// Was the legacy "Spawnmaster" respawn: it read an ms_<name> waypoint whose
// NAME encoded the delay and the resref to spawn, then had the 'spawnmaster'
// placeable CreateObject it. Every ms_-tagged waypoint has since been removed
// from the module, so that lookup resolved to an empty resref at an invalid
// location and nothing ever came back. Now on the standard respawn path
// (nw_c2_default7 -> se_respawn_inc, 900s), like staticspawn.nss.

void main()
{
    SpeakString("Dol Gulgur is under attack! Rally Servants of Sauron to Mirkwoods!", TALKVOLUME_SHOUT);
    ExecuteScript("nw_c2_default7", OBJECT_SELF);
}

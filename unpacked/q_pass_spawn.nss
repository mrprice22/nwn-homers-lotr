// Pass the Pass (roadmap: pass-the-pass)
// (Re)spawn helper for the two quest NPCs. Fired from the area OnEnter wrapper
// q_pass_enter for both foothillsofthemi (giver) and mistymountainsb
// (quartermaster). GetWaypointByTag is global, so either area's OnEnter spawns
// whichever NPCs have a placed waypoint. No-ops until the admin places the
// waypoints (see admin-action-required.md) and never double-spawns.
void main()
{
    object oW1 = GetWaypointByTag("AP_passthepass_1");
    if (GetIsObjectValid(oW1) && !GetIsObjectValid(GetObjectByTag("q_pass_capt")))
        CreateObject(OBJECT_TYPE_CREATURE, "q_pass_capt", GetLocation(oW1));

    object oW3 = GetWaypointByTag("AP_passthepass_3");
    if (GetIsObjectValid(oW3) && !GetIsObjectValid(GetObjectByTag("q_pass_qm")))
        CreateObject(OBJECT_TYPE_CREATURE, "q_pass_qm", GetLocation(oW3));
}

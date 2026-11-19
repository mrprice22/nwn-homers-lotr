//::///////////////////////////////////////////////
//:: FileName at_038
//:: King Theoden: the Helm reward. Only after a verified turn-in (at_036
//:: sets THEODEN_CHOICE), and only one pick per turn-in
//:: (roadmap: mystic-theoden-quest-state).
//:://////////////////////////////////////////////
void main()
{
    object oPC = GetPCSpeaker();
    if (!GetLocalInt(oPC, "THEODEN_CHOICE"))
        return;
    DeleteLocalInt(oPC, "THEODEN_CHOICE");

    CreateItemOnObject("helmoftheriderma", oPC, 1);
}

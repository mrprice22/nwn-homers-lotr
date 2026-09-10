// cp_crowntick -- Crash Party: the Crown of Cacophony's noise chain.
//
// Split out of cp_crown.nss because that script is the equip/unequip handler and
// must not be re-entered by a timer; this is the timer.
//
// Stops itself the moment CP_CROWN_ON goes away, so taking the crown off ends it
// within one tick. Same one-chain-per-wearer guard as cp_tipsy: CP_CROWN_NEXT is
// a timestamp, not a flag, because a flag stranded TRUE by a server restart
// would silence the crown permanently.

#include "cp_inc"

const string CP_CROWN_ON   = "CP_CROWN_ON";
const string CP_CROWN_NEXT = "CP_CROWN_NEXT";

string CP_CrownNoise()
{
    switch (Random(8))
    {
        case 0: return "as_an_rooster1";
        case 1: return "as_an_cow1";
        case 2: return "as_an_dogbark6";
        case 3: return "as_an_catscrech2";
        case 4: return "as_an_crow1";
        case 5: return "as_pl_belchingm1";
        case 6: return "as_an_owlhoot1";
    }
    return "as_an_ratssqeak1";
}

void main()
{
    object oPC = OBJECT_SELF;
    if (!GetIsPC(oPC)) return;
    if (!GetLocalInt(oPC, CP_CROWN_ON)) { DeleteLocalInt(oPC, CP_CROWN_NEXT); return; }

    AssignCommand(oPC, PlaySound(CP_CrownNoise()));

    int nDelay = Random(4) + 3;
    SetLocalInt(oPC, CP_CROWN_NEXT, CP_Now() + nDelay + 5);
    DelayCommand(IntToFloat(nDelay), ExecuteScript("cp_crowntick", oPC));
}

// The Last Drop at Frogmorton Inn (roadmap: frogmorton-last-drop)
// StartingConditional on Rigrin's puzzle entry: always TRUE (the done-today
// branch is checked first in the dialogue), sets token 6330 to this month's
// "custom of the cask". The rule hints at an attribute of exactly one of the
// five claimants; the correct claimant is ((month-1) % 5) + 1:
//   1 Marigold Bunce (brewed it)   2 Poppy Thistlewool (paid for it)
//   3 Hob Broadbelt (tapped it)    4 Ned Puddifoot (hauled it)
//   5 Daisy Goodbody (won it at darts)
// Keep this mapping in sync with q_frog_winc.nss.

int StartingConditional()
{
    string sRule;
    switch (GetCalendarMonth())
    {
        case 1:  sRule = "The hand that stirred the mash pours the last of it."; break;
        case 2:  sRule = "The coin that bought the barrel drains it."; break;
        case 3:  sRule = "Who opened the cask must be the one to close it."; break;
        case 4:  sRule = "The back that bore the barrel gets the bottom of it."; break;
        case 5:  sRule = "The dregs go to the steadiest hand at the dartboard."; break;
        case 6:  sRule = "The brewer's own kin want for nothing while the brew lasts."; break;
        case 7:  sRule = "The last drop follows the purse that paid for the first."; break;
        case 8:  sRule = "First to sup, last to sup."; break;
        case 9:  sRule = "The carter keeps what the cart didn't spill."; break;
        case 10: sRule = "What was staked on the wager goes to the winner of it."; break;
        case 11: sRule = "The widow of the brewhouse is never left dry."; break;
        default: sRule = "Let the buyer have the bottom of the bargain."; break; // month 12
    }
    SetCustomToken(6330, sRule);
    return TRUE;
}

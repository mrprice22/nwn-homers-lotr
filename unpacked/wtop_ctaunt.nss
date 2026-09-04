// Weather Top's Hidden Court taunts (roadmap: forbidden-realms-key-tier)
//
// ScriptAttacked on the three court blueprints (wtop_crtguard / wtop_crtarcher
// / wtop_crtmage). Identical machinery to wtop_taunt.nss on the hill -- chain
// the Bioware default first so combat AI is untouched, then occasionally shout
// -- but the court's lines are the court's, not the hill's: down here the
// throne is in the room.
//
// Gated twice (1-in-8 roll AND a 30s per-creature cooldown) because OnAttacked
// fires many times per round and area028 stands 51 of these. Without the
// cooldown a party pulling one wing would drown in chat.

const string WTOP_CT_AT  = "WTOP_TAUNT_AT";
const int    WTOP_CT_GAP = 30;

void main()
{
    ExecuteScript("x2_def_attacked", OBJECT_SELF);

    if (!GetIsPC(GetLastAttacker())) return;
    if (d8() != 1) return;

    int nNow = (GetTimeHour() * 3600) + (GetTimeMinute() * 60) + GetTimeSecond();
    int nLast = GetLocalInt(OBJECT_SELF, WTOP_CT_AT);
    if (nLast && (nNow - nLast) < WTOP_CT_GAP && nNow >= nLast) return;
    SetLocalInt(OBJECT_SELF, WTOP_CT_AT, nNow);

    string sLine;
    switch (d6())
    {
        case 1:  sLine = "You stand in the King's house!";                break;
        case 2:  sLine = "The court does not sleep. It only waits.";      break;
        case 3:  sLine = "Kneel, or be knelt.";                           break;
        case 4:  sLine = "The Queen has already counted your dead.";      break;
        case 5:  sLine = "No one leaves the hall by the door they came.";  break;
        default: sLine = "For the throne beneath the hill!";              break;
    }

    SpeakString(sLine, TALKVOLUME_TALK);
}

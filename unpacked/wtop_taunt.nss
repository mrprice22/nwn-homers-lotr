// Weather Top / Amon Sul guard taunts (roadmap: forbidden-realms-key-tier)
//
// ScriptAttacked on weathertopfighte and weathertoparc001. Chains the Bioware
// default first so combat AI is untouched, then occasionally shouts a line.
//
// "Occasionally" matters: OnAttacked fires many times per fight, so this is
// gated twice -- a 1-in-8 roll AND a per-creature cooldown, so one guard cannot
// shout twice inside 30 seconds no matter how hard it is being hit. With a
// whole garrison engaged the party still hears the hill talk back regularly.
//
// SpeakString, not ActionSpeakString: the Action form queues onto the combat
// action list and would interrupt the guard's attacks.

const string WTOP_TAUNT_AT = "WTOP_TAUNT_AT";   // game-seconds of the last shout
const int    WTOP_TAUNT_GAP = 30;               // seconds between shouts

void main()
{
    // Default combat response first -- never let flavour change how they fight.
    ExecuteScript("x2_def_attacked", OBJECT_SELF);

    if (!GetIsPC(GetLastAttacker())) return;
    if (d8() != 1) return;

    // Cheap monotonic clock: hours since module start, in seconds, plus the
    // in-hour seconds. Good enough to space shouts out.
    int nNow = (GetTimeHour() * 3600) + (GetTimeMinute() * 60) + GetTimeSecond();
    int nLast = GetLocalInt(OBJECT_SELF, WTOP_TAUNT_AT);
    if (nLast && (nNow - nLast) < WTOP_TAUNT_GAP && nNow >= nLast) return;
    SetLocalInt(OBJECT_SELF, WTOP_TAUNT_AT, nNow);

    string sLine;
    switch (d6())
    {
        case 1:  sLine = "For the royal court!";                       break;
        case 2:  sLine = "The hill is ours. It has always been ours."; break;
        case 3:  sLine = "You will not pass the ring of stones!";      break;
        case 4:  sLine = "Down, grave-robber!";                        break;
        case 5:  sLine = "The King is watching. Die well.";            break;
        default: sLine = "Amon Sul stands!";                           break;
    }

    SpeakString(sLine, TALKVOLUME_TALK);
}

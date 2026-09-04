// Weathertop Royal Magus -- Greater Ruin (roadmap: forbidden-realms-key-tier)
//
// ScriptEndRound on wtop_crtmage. Chains the module default first so the
// Jasperre combat AI is untouched, then throws Greater Ruin (SPELL_EPIC_RUIN,
// spells.2da row 640 -- the epic spell whose own VFX constant is
// VFX_FNF_GREATER_RUIN) at the nearest enemy player, once per minute.
//
// Cast with bCheat = TRUE, so the Magus needs neither FEAT_EPIC_SPELL_RUIN nor
// a prepared slot. That is deliberate: a spell SLOT empties for the rest of the
// fight, and epic spell uses only come back on a rest, so a slot-based Ruin
// would fire once ever and then never again however long the fight ran. The
// admin asked for one that refreshes every minute, and a scripted cooldown is
// the only thing that actually refreshes.
//
// The cooldown is REAL seconds (a local flag cleared by DelayCommand), not the
// game-clock arithmetic wtop_taunt.nss uses for its shout spacing -- game hours
// run far faster than real ones, and "once per minute" here means a minute.
// A DelayCommand on a creature is dropped when that creature is destroyed, so a
// Magus that dies and respawns comes back with Ruin ready, which is correct.

const string WTOP_RUIN_CD = "WTOP_RUIN_CD";
const float  WTOP_RUIN_REFRESH = 60.0;

void main()
{
    ExecuteScript("x2_def_endcombat", OBJECT_SELF);

    if (GetLocalInt(OBJECT_SELF, WTOP_RUIN_CD)) return;

    object oTarget = GetNearestCreature(CREATURE_TYPE_REPUTATION,
                                        REPUTATION_TYPE_ENEMY, OBJECT_SELF, 1,
                                        CREATURE_TYPE_PLAYER_CHAR,
                                        PLAYER_CHAR_IS_PC);
    if (!GetIsObjectValid(oTarget)) return;
    if (GetIsDead(oTarget)) return;

    SetLocalInt(OBJECT_SELF, WTOP_RUIN_CD, TRUE);
    DelayCommand(WTOP_RUIN_REFRESH,
                 SetLocalInt(OBJECT_SELF, WTOP_RUIN_CD, FALSE));

    ActionCastSpellAtObject(SPELL_EPIC_RUIN, oTarget, METAMAGIC_ANY, TRUE);
}

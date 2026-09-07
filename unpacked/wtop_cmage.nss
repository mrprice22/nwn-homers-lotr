// Weathertop Royal Magus -- the court's heavy artillery
//:: (roadmap: forbidden-realms-key-tier, wtop-court-combat-defects)
//
// ScriptEndRound on wtop_crtmage. Chains the module default first so the stock
// BioWare combat AI is untouched (x2_def_endcombat -> nw_i0_generic; NOT the
// Jasperre AI, which no Weathertop blueprint uses), then throws ONE of three
// heavy spells at the nearest enemy player.
//
// The Magus's ordinary book -- the level 8 and 9 list -- lives in its
// SpecAbilityList and is chosen by that AI. Only the three below are scripted,
// and they are scripted for one reason: an AI-chosen talent cannot be
// rate-limited, and these three must be.
//
//   SPELL_EPIC_RUIN                  up to 10,000 damage, single target
//   SPELL_MORDENKAINENS_DISJUNCTION  strips the party's buffs wholesale
//   SPELL_EPIC_MUMMY_DUST            a hostile Mummy Reaper (see below)
//
// COOLDOWNS ARE COURT-WIDE, NOT PER MAGUS. The Hidden Court fields several
// Magi; on a per-creature timer a party walking into the middle level ate every
// one of these at once, which is not difficulty, it is a coin flip. The flag
// therefore lives on the AREA -- the same area-scoped-state pattern
// forge_inc.nss uses -- so at most one Ruin, one Disjunction and one Mummy Dust
// land in the court per minute however many Magi are standing. Each Magus still
// acts every round; it just casts from its own book when the big three are hot.
//
// Cast with bCheat = TRUE. The Magus does hold the matching epic feats (874
// Mummy Dust, 876 Hellball, 878 Ruin), but a spell SLOT empties for the rest of
// the fight and epic uses only come back on a rest, so a slot-based cast would
// fire once ever however long the fight ran. A scripted cooldown is the only
// thing that actually refreshes.
//
// The cooldown is REAL seconds (an area local cleared by DelayCommand), not the
// game-clock arithmetic wtop_taunt.nss uses for its shout spacing -- game hours
// run far faster than real ones, and "once per minute" here means a minute.
// A DelayCommand assigned to the AREA survives the caster's death, which is
// what makes the cooldown the court's rather than the creature's.
//
// Mummy Dust: x2_s2_mumdust.nss branches on GetIsPC, so an NPC cast creates
// wtop_mreaper (FactionID 1) rather than the player's Commoner-faction
// henchman, capped at 2 live in the area.

const float WTOP_MAGE_REFRESH = 60.0;

const string WTOP_CD_RUIN  = "WTOP_CD_RUIN";
const string WTOP_CD_DISJ  = "WTOP_CD_DISJ";
const string WTOP_CD_DUST  = "WTOP_CD_DUST";

// TRUE if this court has the spell available, and claims it if so.
int WtopMageClaim(object oArea, string sFlag)
{
    if (GetLocalInt(oArea, sFlag)) return FALSE;

    SetLocalInt(oArea, sFlag, TRUE);
    AssignCommand(oArea,
        DelayCommand(WTOP_MAGE_REFRESH, DeleteLocalInt(oArea, sFlag)));
    return TRUE;
}

void main()
{
    ExecuteScript("x2_def_endcombat", OBJECT_SELF);

    object oArea = GetArea(OBJECT_SELF);

    object oTarget = GetNearestCreature(CREATURE_TYPE_REPUTATION,
                                        REPUTATION_TYPE_ENEMY, OBJECT_SELF, 1,
                                        CREATURE_TYPE_PLAYER_CHAR,
                                        PLAYER_CHAR_IS_PC);
    if (!GetIsObjectValid(oTarget)) return;
    if (GetIsDead(oTarget)) return;

    // Order is deliberate: strip the party first when the chance comes up, then
    // hit them, then add bodies. Only one is cast per round.
    if (WtopMageClaim(oArea, WTOP_CD_DISJ))
    {
        ActionCastSpellAtObject(SPELL_MORDENKAINENS_DISJUNCTION, oTarget,
                                METAMAGIC_ANY, TRUE);
        return;
    }

    if (WtopMageClaim(oArea, WTOP_CD_RUIN))
    {
        ActionCastSpellAtObject(SPELL_EPIC_RUIN, oTarget, METAMAGIC_ANY, TRUE);
        return;
    }

    if (WtopMageClaim(oArea, WTOP_CD_DUST))
    {
        ActionCastSpellAtLocation(SPELL_EPIC_MUMMY_DUST, GetLocation(oTarget),
                                  METAMAGIC_ANY, TRUE);
    }
}

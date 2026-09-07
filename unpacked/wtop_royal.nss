// The Weathertop King and Queen -- the royal bond (roadmap: forbidden-realms-key-tier)
//
// ScriptEndRound on weathertopkin004 and weathertopque003. The admin's brief:
// "king and queen should compliment eachother and together be tougher than the
// chosen of helms deep, or gandalf". Individually they already clear that bar
// (Theoden's Chosen 8200 HP / AC 15; Gandalf the Gray 8017 HP / AC 32 / 115
// feats; the King is 9500 / AC 75 / 169 feats and the Queen 10000 / AC 72).
// What makes them a PAIR is this script:
//
//   BOND  -- while both are alive each carries the other's protection:
//            damage reduction and regeneration. Neither can be burst down while
//            the other still stands, so a party that splits its damage across
//            both thrones gets nowhere.
//   GRIEF -- the moment one falls the survivor loses the bond and turns
//            dangerous instead of durable: dodge AC, movement speed and a
//            negative-damage retaliation shield. Killing one is not half the
//            fight, it is the start of the worse half.
//
// The pairing is the whole point: focus one down and you face a faster, harder
// survivor; spread damage and you face two that will not die. There is no order
// that makes this cheap.
//
// WHY NO ATTACK OR DAMAGE BONUS HERE. Both are pooled module-wide through
// bonus_pool_inc.nss, because same-type effects are max-of in NWN and the
// engine additionally clamps weapon-plus-effect attack bonus to
// GetAttackBonusLimit() (20 by default). An EffectAttackIncrease dropped on a
// creature whose attack bonus is already ~150 from BAB and Strength would be
// worth nothing at all, and registering a new pooled source means editing the
// ledger's source table -- a shared file the legendary feats and Bard Song
// depend on. Everything applied below is outside that argument: damage
// reduction, regeneration, dodge AC, speed and a damage shield all stack fine
// against themselves as single sources.
//
// Effects are supernatural (undispellable, and they survive a rest) and tagged,
// so the grief transition can strip exactly the bond and nothing else.

const string RR_KING  = "weathertopkin004";
const string RR_QUEEN = "weathertopque003";

const string TAG_BOND  = "wtop_royal_bond";
const string TAG_GRIEF = "wtop_royal_grief";

const string WTOP_STATE     = "WTOP_ROYAL_STATE";   // 0 none / 1 bonded / 2 grieving
const string WTOP_HEAL_CD   = "WTOP_ROYAL_HEALCD";
const float  WTOP_HEAL_GAP  = 30.0;
const int    WTOP_HEAL_AT   = 50;                   // percent of max HP

// The other throne, alive, in this area. Deliberately area-scoped: the court is
// one room and a hill-side copy must never satisfy the bond.
object WtopPartner(string sResRef)
{
    object oArea = GetArea(OBJECT_SELF);
    object oObj  = GetFirstObjectInArea(oArea);
    while (GetIsObjectValid(oObj))
    {
        if (GetObjectType(oObj) == OBJECT_TYPE_CREATURE
            && GetResRef(oObj) == sResRef
            && !GetIsDead(oObj))
            return oObj;
        oObj = GetNextObjectInArea(oArea);
    }
    return OBJECT_INVALID;
}

// Remove every effect carrying sTag.
//
// Counted first, then removed one restart at a time. RemoveEffect() inside a
// GetFirstEffect/GetNextEffect loop skips the entry after each removal, so a
// partial strip could leave a residual grief link behind -- and the next state
// flip then applied a SECOND permanent +20 AC on top of it, which no debuff can
// see past (roadmap wtop-court-combat-defects). At most two of these are ever
// held at once, so the restart is free.
void WtopStrip(object oCre, string sTag)
{
    int nFound = 0;
    effect e = GetFirstEffect(oCre);
    while (GetIsEffectValid(e))
    {
        if (GetEffectTag(e) == sTag) nFound++;
        e = GetNextEffect(oCre);
    }

    // One clean walk per tagged effect: restart, remove the first match, stop.
    int i;
    for (i = 0; i < nFound; i++)
    {
        e = GetFirstEffect(oCre);
        while (GetIsEffectValid(e))
        {
            if (GetEffectTag(e) == sTag)
            {
                RemoveEffect(oCre, e);
                break;
            }
            e = GetNextEffect(oCre);
        }
    }
}

void WtopApplyBond(object oCre)
{
    effect eLink = EffectLinkEffects(
        EffectDamageReduction(30, DAMAGE_POWER_PLUS_TWENTY),
        EffectRegenerate(200, 6.0));
    eLink = TagEffect(SupernaturalEffect(eLink), TAG_BOND);
    ApplyEffectToObject(DURATION_TYPE_PERMANENT, eLink, oCre);
}

void WtopApplyGrief(object oCre)
{
    effect eLink = EffectLinkEffects(
        // NATURAL, not the default dodge bucket: ruleset.2da caps dodge at
        // MAX_AC_DODGE_MOD 20, so a bare EffectACIncrease(20) both wasted most
        // of itself and filled the ceiling a Curse Song penalty needs to reach
        // (roadmap wtop-court-combat-defects).
        EffectLinkEffects(EffectACIncrease(20, AC_NATURAL_BONUS),
                          EffectMovementSpeedIncrease(50)),
        EffectDamageShield(50, DAMAGE_BONUS_2d12, DAMAGE_TYPE_NEGATIVE));
    eLink = TagEffect(SupernaturalEffect(eLink), TAG_GRIEF);
    ApplyEffectToObject(DURATION_TYPE_PERMANENT, eLink, oCre);

    SpeakString(GetResRef(OBJECT_SELF) == RR_KING
                ? "You have taken my Queen. Now there is nothing left to spare you for."
                : "My King is down. I will not be taken alive a second time.",
                TALKVOLUME_TALK);
}

void main()
{
    ExecuteScript("x2_def_endcombat", OBJECT_SELF);

    string sSelf = GetResRef(OBJECT_SELF);
    if (sSelf != RR_KING && sSelf != RR_QUEEN) return;

    object oPartner = WtopPartner(sSelf == RR_KING ? RR_QUEEN : RR_KING);
    int nState = GetLocalInt(OBJECT_SELF, WTOP_STATE);

    if (GetIsObjectValid(oPartner))
    {
        if (nState != 1)
        {
            WtopStrip(OBJECT_SELF, TAG_GRIEF);
            WtopApplyBond(OBJECT_SELF);
            SetLocalInt(OBJECT_SELF, WTOP_STATE, 1);
        }

        // The Queen is the half of the pair that mends: she pulls the King back
        // off the floor once every 30 seconds while he is under half health.
        // The King has no answer for her in kind -- which is the reason a party
        // that knows the fight kills the Queen first, and then has to deal with
        // a grieving King.
        if (sSelf == RR_QUEEN
            && !GetLocalInt(OBJECT_SELF, WTOP_HEAL_CD)
            && GetCurrentHitPoints(oPartner) * 100
               < GetMaxHitPoints(oPartner) * WTOP_HEAL_AT)
        {
            SetLocalInt(OBJECT_SELF, WTOP_HEAL_CD, TRUE);
            DelayCommand(WTOP_HEAL_GAP,
                         SetLocalInt(OBJECT_SELF, WTOP_HEAL_CD, FALSE));
            // Applied directly, NOT cast. Both royals are Race 24 (Undead) and
            // stock nw_s0_heal treats an undead target as an attack, gated on
            // !GetIsReactionTypeFriendly() -- so an ally-cast Heal on the King
            // resolved to nothing at all and the Queen has never once picked
            // him up (roadmap wtop-court-combat-defects). EffectHeal has no
            // such rule.
            int nMend = GetMaxHitPoints(oPartner) / 4;
            ApplyEffectToObject(DURATION_TYPE_INSTANT, EffectHeal(nMend),
                                oPartner);
            ApplyEffectToObject(DURATION_TYPE_INSTANT,
                                EffectVisualEffect(VFX_IMP_HEALING_X), oPartner);
            SpeakString(GetResRef(OBJECT_SELF) == RR_QUEEN
                        ? "Rise, my King. They are not done with us yet."
                        : "Rise.", TALKVOLUME_TALK);
        }
        return;
    }

    if (nState != 2)
    {
        WtopStrip(OBJECT_SELF, TAG_BOND);
        WtopApplyGrief(OBJECT_SELF);
        SetLocalInt(OBJECT_SELF, WTOP_STATE, 2);
    }
}

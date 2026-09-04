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

void WtopStrip(object oCre, string sTag)
{
    effect e = GetFirstEffect(oCre);
    while (GetIsEffectValid(e))
    {
        if (GetEffectTag(e) == sTag) RemoveEffect(oCre, e);
        e = GetNextEffect(oCre);
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
        EffectLinkEffects(EffectACIncrease(20),
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
            ActionCastSpellAtObject(SPELL_HEAL, oPartner, METAMAGIC_ANY, TRUE);
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

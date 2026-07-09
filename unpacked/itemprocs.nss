itemproperty GetNewProperty(object oItem)
{
   object oPC = GetPCSpeaker();
   string sProp = GetLocalString(oPC, "MODIFY_PROPERTY");
   int iParam1 = GetLocalInt(oPC, "MODIFY_PARAM1");
   int iParam2 = GetLocalInt(oPC, "MODIFY_PARAM2");
   int iParam3 = GetLocalInt(oPC, "MODIFY_PARAM3");
   if (iParam3 == -1)
      iParam3 = 1;

   itemproperty ip;

   if ( sProp == "Ability Bonus")
       ip = ItemPropertyAbilityBonus(iParam2, iParam3);
   else if ( sProp == "AC Bonus")
       ip = ItemPropertyACBonus(iParam3);
   else if ( sProp == "Enhancement")
       ip = ItemPropertyEnhancementBonus(iParam3);
   else if ( sProp == "Bonus Feat")
       ip = ItemPropertyBonusFeat(iParam3);
   else if ( sProp == "Damage Bonus")
       ip = ItemPropertyDamageBonus(iParam2, iParam3);
   else if ( sProp == "Damage Immunity")
       ip = ItemPropertyDamageImmunity(iParam2, iParam3);
   else if ( sProp == "Damage Reduction")
       ip = ItemPropertyDamageReduction(iParam2, iParam3);
   else if ( sProp == "Damage Resistance")
       ip = ItemPropertyDamageResistance(iParam2, iParam3);
   else if ( sProp == "Darkvision")
       ip = ItemPropertyDarkvision();
   else if ( sProp == "Haste")
       ip = ItemPropertyHaste();
   else if ( sProp == "Holy Avenger")
       ip = ItemPropertyHolyAvenger();
   else if ( sProp == "Improved Magic Resistance")
       ip = ItemPropertyBonusSpellResistance(iParam3);
   else if ( sProp == "Improved Saving Throws")
       ip = ItemPropertyBonusSavingThrow(iParam2, iParam3);
   else if ( sProp == "Improved Saving Throws Vs")
       ip = ItemPropertyBonusSavingThrowVsX(iParam2, iParam3);
   else if ( sProp == "Light")
       ip = ItemPropertyLight(iParam2, iParam3);
   else if ( sProp == "Keen")
       ip = ItemPropertyKeen();
   else if ( sProp == "Massive Criticals")
       ip = ItemPropertyMassiveCritical(iParam3);
   else if ( sProp == "Mighty")
       ip = ItemPropertyMaxRangeStrengthMod(iParam3);
   else if ( sProp == "Miscellaneous Immunity")
       ip = ItemPropertyImmunityMisc(iParam3);
   else if ( sProp == "Spell Immunity Specific")
       ip = ItemPropertySpellImmunitySpecific(iParam3);
   else if ( sProp == "On Hit Properties")
       ip = ItemPropertyOnHitProps(iParam1, iParam2, iParam3);
   else if ( sProp == "Regeneration")
       ip = ItemPropertyRegeneration(iParam3);
   else if ( sProp == "Skill Bonus")
       ip = ItemPropertySkillBonus(iParam2, iParam3);
   else if ( sProp == "Attack Bonus")
       ip = ItemPropertyAttackBonus(iParam3);
   else if ( sProp == "Vampiric Regeneration")
       ip = ItemPropertyVampiricRegeneration(iParam3);
   else if ( sProp == "True Seeing")
       ip = ItemPropertyTrueSeeing();
   else if ( sProp == "Freedom of Movement")
       ip = ItemPropertyFreeAction();
   else if ( sProp == "Weight Reduction")
       ip = ItemPropertyWeightReduction(iParam3);
   else if ( sProp == "Arcane Spell Failure")
       ip = ItemPropertyArcaneSpellFailure(iParam3);
   else if ( sProp == "Unlimited Ammo")
       ip = ItemPropertyUnlimitedAmmo(iParam3);
   return ip;
}

//Add property ip to object oItem
void CustomAddProperty(object oItem, itemproperty ip)
{
    //Find and remove existing property with same type as ip, then add ip
    int iTyp = GetItemPropertyType(ip);
    int iSubTyp = GetItemPropertySubType(ip);

    //Loop through item properties looking for match
    itemproperty ipLoop = GetFirstItemProperty(oItem);
    int bFound = FALSE;
    while ((! bFound) && GetIsItemPropertyValid(ipLoop))
    {
        int iTyp1 = GetItemPropertyType(ipLoop);
        int iSubTyp1 = GetItemPropertySubType(ipLoop);

        bFound = ((iTyp1 == iTyp) && ((iSubTyp == -1) || (iSubTyp1 == iSubTyp)));
        if (! bFound)
            ipLoop = GetNextItemProperty(oItem);
    }

    if (bFound)
        RemoveItemProperty(oItem, ipLoop);
    if (GetLocalInt(GetPCSpeaker(), "MODIFY_PARAM3") > -1)
        AddItemProperty(DURATION_TYPE_PERMANENT, ip, oItem);
}

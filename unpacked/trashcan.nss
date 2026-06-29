void main()
{
    object oItem = GetFirstItemInInventory(OBJECT_SELF);
    int iRoll = d100(1);

    while (GetIsObjectValid(oItem)) {
       DestroyObject(oItem, 0.0f);
       oItem = GetNextItemInInventory(OBJECT_SELF);
    }
    if (iRoll > 1)
    {
       SpeakString("*BURP!!*", TALKVOLUME_TALK);
    }
}

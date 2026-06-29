// openstoremeth — opens Methonash's Well-Mart (100k buy cap) for the speaker.
// Clone of openstore061 targeting the "methmart" store instead of "wellshop".
#include "store_appr_inc"
void main()
{
    object oStore = GetNearestObjectByTag("methmart");
    if (GetObjectType(oStore) == OBJECT_TYPE_STORE)
    {
        OpenStoreAppr(oStore, GetPCSpeaker());
    }
    else
    {
        ActionSpeakStringByStrRef(53090, TALKVOLUME_TALK);
    }
}

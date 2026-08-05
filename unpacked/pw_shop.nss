// pw_shop.nss - opens Odo Proudfoot's leaf counter (pw_odostore).
// (roadmap: concerning-pipeweed)
//
// Attached as the Script on the leaf-counter reply of q_hob_conv.dlg, behind
// the pw_c_shop StartingConditional.
//
// The store object is created on demand at Odo's feet and cached on him, so
// there is no store instance to position in a .git.json. One store object per
// Odo, reused for the rest of the module's life.
//
// Deliberately plain OpenStore, NOT OpenStoreAppr: pw_odostore has
// MaxBuyPrice 0 (Odo buys nothing at all), so there is no buy cap for
// Appraise to scale, and the "buy-from-you cap: unlimited" line
// OpenStoreAppr prints for uncapped stores would be actively misleading here.

void main()
{
    object oPC  = GetPCSpeaker();
    object oOdo = OBJECT_SELF;
    if (!GetIsPC(oPC)) return;

    object oStore = GetLocalObject(oOdo, "PW_ODO_STORE");
    if (!GetIsObjectValid(oStore))
    {
        oStore = CreateObject(OBJECT_TYPE_STORE, "pw_odostore",
                              GetLocation(oOdo));
        SetLocalObject(oOdo, "PW_ODO_STORE", oStore);
    }

    if (GetObjectType(oStore) == OBJECT_TYPE_STORE)
        OpenStore(oStore, oPC);
}

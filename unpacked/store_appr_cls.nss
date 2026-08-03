// store_appr_cls.nss - STORE_ON_CLOSE handler for the per-PC Appraise store
// copies created by OpenStoreAppr (store_appr_inc). Destroys the throwaway copy
// as soon as the player closes it. Only ever set on copies (guarded by the
// STORE_APPR_COPY flag), never on a real placed store.
void main()
{
    if (GetLocalInt(OBJECT_SELF, "STORE_APPR_COPY"))
        DestroyObject(OBJECT_SELF, 0.5);
}

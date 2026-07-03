void main()
{
   object listener = GetNearestObjectByTag("listener", OBJECT_SELF);
   if (listener != OBJECT_INVALID && GetDistanceBetween(OBJECT_SELF, listener) < 3.0)
      DestroyObject(listener); // only destroy this trigger's own runtime listener
}

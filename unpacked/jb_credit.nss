// jb_credit.nss - credit the room for music that has just finished playing.
//
// Run with ExecuteScript from JB_Reconcile (jb_db.nss) with the area as
// OBJECT_SELF and the number of seconds in the JB_CREDIT_SEC local. It exists
// as a separate script purely to break an include cycle: jb_buff_inc includes
// jb_db, so jb_db cannot call into it directly.
#include "jb_buff_inc"

void main()
{
    object oArea = OBJECT_SELF;
    int nSeconds = GetLocalInt(oArea, JB_CREDIT_SEC);
    DeleteLocalInt(oArea, JB_CREDIT_SEC);

    JB_CreditListeners(oArea, nSeconds);
}

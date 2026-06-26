// merit_mypend — Reply action: build the speaker's own pending-request list
// (tokens 5050-5059) so they can cancel for a refund.
#include "merit_redeem"
void main()
{
    Merit_BuildMyPending(GetPCSpeaker());
}

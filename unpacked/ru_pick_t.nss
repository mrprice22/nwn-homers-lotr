// ru_pick_t - reply action: browse the updates that still need testing.
#include "ru_db"
void main()
{
    RU_OpenBucket(GetPCSpeaker(), RU_TESTING);
}

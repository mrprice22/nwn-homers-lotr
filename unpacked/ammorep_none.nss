// Gate for the "you carry no ammunition" entry: the scan found nothing to copy.

int StartingConditional()
{
    return GetLocalInt(GetPCSpeaker(), "AMMOREP_COUNT") == 0;
}

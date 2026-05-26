int GetBestClass(object oChar)
{
    int nBest = GetLevelByPosition(1, oChar);
    int i;
    for (i = 2; i <= 4; i++)
    {
        int nLevel = GetLevelByPosition(i, oChar);
        if (nLevel > nBest) nBest = nLevel;
    }
    return nBest;
}

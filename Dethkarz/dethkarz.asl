state("Dethkarz")
{
    int timeNow : 0x125ae8;
    int rate : 0x406bf0;
    int scrPtr : 0x125AEC;
}

startup
{
    vars.curTime = 0f;
    vars.loadingScrPtr = 0x4FE788;
}

start
{
    vars.curTime = 0f;
}


update
{
    int delta = (current.timeNow - old.timeNow);
    if (delta > 0 && delta < 10 && current.scrPtr != vars.loadingScrPtr)
    {
        vars.curTime += delta / (float)current.rate;
    }
}

isLoading
{
    return true;
}

gameTime
{
    return TimeSpan.FromSeconds(vars.curTime);
}
// DOOMIT: HELL ON TEUFORT AUTOSPLITTER
// BY 2838
// VERSION 1.0 - 15TH NOVEMBER 2020

state("Doomnit Alpha")
{
    // is the player inside a level or in a timescreen?
    byte isActive : "Doomnit Alpha.exe", 0x18d35c;

    // pointer to the time string of the timescreen
    string2 endText : "Doomnit Alpha.exe", 0x18D3D8, 0x3C4, 0xFB;

    // is the player in the menus?
    byte isMenu : "Doomnit Alpha.exe", 0x18d3f8;

    // internal timer
    int timer : "Doomnit Alpha.exe", 0x18D4B8;

    // music name strings
    string64 musicName1 : "Doomnit Alpha.exe", 0x18F134, 0x490, 0x140;
    string64 musicName2 : "Doomnit Alpha.exe", 0x189690, 0xD38, 0x1C0;

    // UNUSED
    //double xPos: "Doomnit Alpha.exe", 0x189430, 0xD4, 0x4, 0xC, 0x10;
    //double yPos: "Doomnit Alpha.exe", 0x189430, 0xD4, 0x4, 0xC, 0x38;
    //byte isFinished : "Doomnit Alpha.exe", 0x18F2B0;
    //double timer2 : "Doomnit Alpha.exe", 0x18937C, 0x25C, 0x0, 0x104, 0x4, 0x330;
}

init
{
    vars.splitOnNextScreen = false;
    vars.secondLvlStartTime = 0.0f;
}

startup
{
    vars.curTime = 0.0f;
    vars.test = 0;

    settings.Add("timesplit", true, "Split on showing Time Screen");
    settings.Add("newlvlsplit", true, "Split on entering a new level");
}

start
{
    if (current.isActive == 1 && current.isMenu == 0 && old.isMenu == 1)
    {
        vars.splitOnNextScreen = false;
        vars.secondLvlStartTime = 0.0f;
        vars.curTime = 0.0f;
        return true;
    }
}

reset
{
    if (current.isActive == 1 && current.isMenu == 0 && old.isMenu == 1)
    {
        vars.splitOnNextScreen = false;
        vars.secondLvlStartTime = 0.0f;
        vars.curTime = 0.0f;
        return true;
    }
}

update
{
    // the game runs at 30 ticks per second
    float delta = (current.timer - old.timer) * (1f / 30f);
    if (delta > 0)
    {
        vars.curTime += delta;
    }
}

split
{
    // initial: check if the time text is either filled in or cleared out when the level is active or right when it goes inactive
    // correctness: is the time text the same as the measured level time?
    bool initial = (old.endText != current.endText && (current.isActive == 1 || (old.isActive == 1 && current.isActive == 0)));
    bool correctness = (current.endText == Math.Floor(vars.curTime - vars.secondLvlStartTime).ToString());

    // for the final split we'll have to monitor the music name variables
    // there are 2 since it bounces between them
    bool checkName1 = current.musicName1 != old.musicName1 && current.musicName1.Contains("snd_gameend");
    bool checkName2 = current.musicName2 != old.musicName2 && current.musicName2.Contains("snd_gameend");
    bool endSplit = (checkName1 || checkName2); 

    if (initial && correctness)
    {
        vars.splitOnNextScreen = true;
        return settings["timesplit"];
    }
    else if (initial && vars.splitOnNextScreen)
    {
        vars.splitOnNextScreen = false;
        vars.secondLvlStartTime = vars.curTime;
        return (endSplit || settings["newlvlsplit"]);
    }
    else if (endSplit)
    {
        return true;
    }
}

isLoading
{
    return true;
}

gameTime
{
    return TimeSpan.FromSeconds((float)vars.curTime);
}
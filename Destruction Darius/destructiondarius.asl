// Destruction Darius Autosplitter
// version 1.0 -- 29/03/2021

// LOGIC
// SCREEN ID:   the game tracks the current sceen using an integer
// IGT:         the game has an internal timer which counts up in milliseconds and is reset with every screen change.

// SPLITTING
//      START:      normal  - when the screen id changes from 2 (menu)
//                  il      - when the current screen is not one of the non-level screens and the game time resets
//      SPLIT:      normal  - when the screen id changes to 24 (level end screen)
//                  chapter - like normal but only if current screen is that of one of the chapters' final level's
//      RESET:      normal  - does NOT reset by its own.
//                  il      - when the current screen is not one of the non-level screens and the game time resets
//                            or the player returns to the menu (screen id changes to 2)

// CREDITS
//      2838        creator
//      the_kovic   testing

state("Destruction Darius")
{
    int inGameTimer: "Destruction Darius.exe", 0xAC9B4, 0xD4; 
    int level: "Destruction Darius.exe", 0xAC9AC, 0x1ec;
}

startup
{
    settings.Add("chapter", false, "Split only on chapter changes instead");
    settings.Add("il", false, "IL Mode, timer resets on level reset");
    vars.nonLevels = new List<int> (new int[] {2, 3, 24, 25});
    vars.finalLevels = new List<int> (new int[] {7, 11, 15, 19, 23});
}

init
{
    vars.time = 0f;
    Func<bool> IsLoading = () => {
        return (vars.nonLevels.Contains(current.level));
    };

    vars.IsLoading = IsLoading;
}

update
{
    float delta = current.inGameTimer - old.inGameTimer;
    if (delta > 0 && !vars.IsLoading())
        vars.time += delta / 1000f;
}

split
{
    if (!settings["chapter"])
        return (!vars.nonLevels.Contains(old.level) && current.level == 24);
    else return (vars.finalLevels.Contains(old.level) && current.level == 24);
}

start
{
    vars.time = 0f;
    if (settings["il"])
        return (!vars.nonLevels.Contains(current.level) && old.inGameTimer > current.inGameTimer);
    return (old.level == 2 && current.level != 2);
}

reset
{
    if (settings["il"])
        return (!vars.nonLevels.Contains(current.level) && old.inGameTimer > current.inGameTimer) 
                || (!vars.nonLevels.Contains(old.level) && current.level == 2);
}

isLoading
{
    return vars.IsLoading();
}

gameTime
{
    return TimeSpan.FromSeconds(vars.time);
}

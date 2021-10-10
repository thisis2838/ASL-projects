// DETHKARZ AUTOSPLITTER
// 10 OCTOBER 2021
// CREDITS
// 2838		development
// Brionac	testing

state("Dethkarz")
{
    int nLapTimerTick : 0x406c54;
    int nGlobalTimerTick : 0x013d618;
    int nRaceState : 0x121d28;
    int nLaps : 0x111F08;
	int pLastFunc : 0x125AEC;
	int nFPSLimit : 0x304678;
	float fLapTimer : 0x111EF8;
}

startup
{
	settings.Add("split", true, "Splitting");
	settings.Add("split-gaincontrol", true, "Split when you gain control of the car", "split");
	settings.Add("split-laps", true, "Split on laps", "split");
	settings.Add("split-ignore1st", true, "Don't split on beginning the first lap", "split-laps");

	settings.Add("time", true, "Timing");
	settings.Add("time-piggyback", true, "Use the lap timer exclusively (will not count menu / pause time)", "time");

	settings.Add("start", true, "Auto-Starting");
	settings.Add("start-gaincontrol", true, "Start when you gain control of the car", "start");
	settings.Add("start-lap", true, "Start on 1st lap", "start");


	vars.listInjections = new List<Tuple<IntPtr, byte[]>>();

    vars.fCurTime = 0f;
	Action<string, string> prints = (tag, msg) => 
	{
		print("[" + tag + "] " + msg);
	};
	vars.prints = prints;
	vars.bLoading = false;
}

init
{
	Func<float> GetCurrentFrameLimit = () =>
	{
		switch ((int)current.nFPSLimit)
		{
			case 0:
				return 1 / 15f;
			case 1:
				return 1 / 30f;
			case 2:
				return 1 / 60f;
		}
		return 1 / 60f;
	};
	vars.GetCurrentFrameLimit = GetCurrentFrameLimit;

	vars.listInjections.Clear();
	Action<IntPtr, byte[]> AddToInjectionList = (ptr, bytes) =>
	{
		game.VirtualProtect(ptr, bytes.Length, MemPageProtect.PAGE_EXECUTE_READWRITE);
		vars.listInjections.Add(new Tuple<IntPtr, byte[]>(ptr, bytes));
	};
	vars.AddToInjectionList = AddToInjectionList;

#region CODE INJECTION

	IntPtr pInjectWorkspace = game.AllocateMemory(100);
	if (pInjectWorkspace == IntPtr.Zero)
		throw new Exception("failed to inject code!");
	else
		vars.prints("MEMORY", "allocated memory at 0x" + pInjectWorkspace.ToString("x"));

	IntPtr pPauseFuncDetour = pInjectWorkspace;
	IntPtr pPauseFuncVal = pInjectWorkspace + 0x20;
	IntPtr pPauseFunc = (IntPtr)0x4549C0;
	byte[] arrPauseFuncValPtr = BitConverter.GetBytes(pPauseFuncVal.ToInt32());
	vars.AddToInjectionList(pPauseFunc, game.ReadBytes(pPauseFunc, 0x6));
	game.WriteJumpInstruction(pPauseFunc, pPauseFuncDetour);
	byte[] arrPauseFuncDetourInsc = new byte[12]
	{
		0x8B, 0x0D, 0x38, 0x72, 0x52, 0x00,
		0xFF, 0x05, arrPauseFuncValPtr[0], arrPauseFuncValPtr[1], arrPauseFuncValPtr[2], arrPauseFuncValPtr[3]
	};
	game.WriteBytes(pPauseFuncDetour, arrPauseFuncDetourInsc);
	game.WriteJumpInstruction(pPauseFuncDetour + 12, pPauseFunc + 6);

	vars.mwPauseCalled = new MemoryWatcher<int>(pPauseFuncVal);
	
#endregion
}

update
{
	if (settings["time-piggyback"])
	{
		float delta = current.fLapTimer - old.fLapTimer;
		vars.fCurTime += delta > 0 ? delta : 0;
		return;
	}

	vars.mwPauseCalled.Update(game);

	if (vars.mwPauseCalled.Changed)
		vars.bLoading = true;

	if (old.nLapTimerTick == 0 && current.nLapTimerTick > 0)
		vars.bLoading = false;

	if (old.pLastFunc != 0x4fe788 && !vars.bLoading)
	{
		int delta = (current.nLapTimerTick - old.nLapTimerTick);

		if (delta == 0f)
			delta = (current.nGlobalTimerTick - old.nGlobalTimerTick);

		vars.fCurTime += (delta > 0 ? delta : 0) * vars.GetCurrentFrameLimit();
	}
}

split
{
	if (!settings["split"] || vars.bLoading || current.nRaceState < 3)
		return false;
	if (settings["split-gaincontrol"] && current.nRaceState == 3 && old.nRaceState == 2)
		return true;
	if (settings["split-laps"] 
	&& ((current.nLaps != old.nLaps && (settings["split-ignore1st"] && current.nLaps > 1)) 
		|| (current.fLapTimer < old.fLapTimer && current.fLapTimer < 0.1)))
		return true;
}

start
{
	vars.fCurTime = 0;

	if (!settings["start"] || vars.bLoading || current.nRaceState < 3)
		return false;
	if (settings["start-gaincontrol"] && current.nRaceState == 3 && old.nRaceState == 2)
		return true;
	if (settings["start-lap"] 
	&& (current.nLaps == 1 && old.nLaps == 0 || (current.fLapTimer < old.fLapTimer && current.fLapTimer < 0.1)))
		return true;
}

isLoading
{
    return true;
}

shutdown
{
	foreach (Tuple<IntPtr, byte[]> injection in vars.listInjections)
		game.WriteBytes(injection.Item1, injection.Item2);
}

gameTime
{
	return TimeSpan.FromSeconds(vars.fCurTime);
}
// DETHKARZ AUTOSPLITTER
// SOMETIME AFTER 17TH OCTOBER 2021 (im not bothered to update this)
// CREDITS
// 2838		development
// Brionac	testing

state("Dethkarz")
{
    int pCamera : 0x141090;
    int nGlobalTimerTick : 0x013d618;
    int nRaceState : 0x121d28;
	int pLastFunc : 0x125AEC;
	float fRate : 0x121cf0;
	bool bIsPaused : 0x1383c0;
	int nCheckpoint : 0x111F10;
}

startup
{
	refreshRate = 60;
	
	Action<string, string> prints = (tag, msg) => 
	{
		print("[DETHKARZ ASL] [" + tag + "] " + msg);
	};
	vars.prints = prints;

	settings.Add("start", true, "Auto-Starting");
	settings.Add("start-gaincontrol", true, "Start when you gain control of the car", "start");
	settings.Add("start-lap", true, "Start on 1st lap", "start");
	settings.Add("start-everylap", false, "IL Mode - Start on any lap", "start");
	settings.SetToolTip("start-everylap", "Start on any lap regardless if the timer is running or not");

	settings.Add("split", true, "Splitting");
	settings.Add("split-gaincontrol", true, "Split when you gain control of the car", "split");
	settings.Add("split-end", true, "Split at the end of races", "split");
	settings.Add("split-laps", true, "Split on laps", "split");
	settings.Add("split-ignore1st", true, "Don't split on beginning the first lap", "split-laps");
	settings.Add("split-checkpoint", false, "Split on reaching new Checkpoint", "split");
	vars.listCheckpointMod = new List<int>(new int[] {5, 10, 20, 30});
	foreach (int x in vars.listCheckpointMod)
		settings.Add("split-checkpoint-every" + x, true, "Every " + x + "th Checkpoint", "split-checkpoint");

	settings.Add("time", true, "Timing");
	settings.Add("time-pauses", true, "Time pauses", "time");
	settings.Add("time-menu", true, "Time menuing", "time");
	settings.Add("time-prerace", false, "Time pre-race camera pan and countdown", "time");
	settings.Add("time-postrace", false, "Time post-race results screen", "time");

	vars.listInjections = new List<Tuple<IntPtr, byte[]>>();

    vars.fCurTime = 0f;
	vars.fTotalLapTime = 0f;

	vars.bLoading = false;
	vars.bPaused = false;

	vars.TimerModel = new TimerModel { CurrentState = timer };
}

init
{
#region CODE INJECTION

	vars.listInjections.Clear();
	Action<IntPtr, byte[]> AddToInjectionList = (ptr, bytes) =>
	{
		game.VirtualProtect(ptr, bytes.Length, MemPageProtect.PAGE_EXECUTE_READWRITE);
		vars.listInjections.Add(new Tuple<IntPtr, byte[]>(ptr, bytes));
	};
	vars.AddToInjectionList = AddToInjectionList;

	IntPtr pInjectWorkspace = game.AllocateMemory(0x1000);
	if (pInjectWorkspace == IntPtr.Zero)
		throw new Exception("failed to inject code!");
	else
		vars.prints("MEMORY", "allocated memory at 0x" + pInjectWorkspace.ToString("x"));

	Action<IntPtr, IntPtr, byte[], int> WriteDetour = (from, to, bytes, preserve) => 
	{
		vars.AddToInjectionList(from, game.ReadBytes(from, preserve));
		game.WriteBytes(to, game.ReadBytes(from, preserve));
		game.WriteJumpInstruction(from, to);
		game.WriteBytes(to + preserve, bytes);
		game.WriteJumpInstruction(to + preserve + bytes.Length, from + preserve);
		vars.prints("MEMORY", "Written detour from 0x" + from.ToString("X") + " to 0x" + to.ToString("X") + " [" + bytes.Length + " bytes]");
	};

	// loading screen function
	IntPtr pLoadScrVal = pInjectWorkspace;
	byte[] arrLoadScrValPtr = BitConverter.GetBytes(pLoadScrVal.ToInt32());
	WriteDetour(
		(IntPtr)0x4549C0, 
		pLoadScrVal + 0x4, 
		new byte[6]
		{
			// inc [pLoadScrVal]
			0xFF, 0x05, arrLoadScrValPtr[0], arrLoadScrValPtr[1], arrLoadScrValPtr[2], arrLoadScrValPtr[3]
		}, 
		6);

	// lap increment function
	IntPtr pLapFuncVal = pInjectWorkspace + 0x100;
	byte[] arrLapFuncValPtr = BitConverter.GetBytes(pLapFuncVal.ToInt32());
	WriteDetour(
		(IntPtr)0x438598, 
		pLapFuncVal + 0x4, 
		new byte[14]
		{
			// cmp esi,(player car ptr)
			0x81, 0xFE, 0x78, 0x1C, 0x51, 0x00,
			// jne (end of func)
			0x75, 0x06,
			// inc [pLapFuncVal]
			0xFF, 0x05, arrLapFuncValPtr[0], arrLapFuncValPtr[1], arrLapFuncValPtr[2], arrLapFuncValPtr[3]
		}, 
		6);

	// lap info reset function
	IntPtr pLapResetVal = pInjectWorkspace + 0x300;
	byte[] arrLapResetValPtr = BitConverter.GetBytes(pLapResetVal.ToInt32());
	WriteDetour(
		(IntPtr)0x438577, 
		pLapResetVal + 0x4, 
		new byte[14]
		{
			// cmp esi,(player car ptr)
			0x81, 0xFE, 0x78, 0x1C, 0x51, 0x00,
			// jne (end of func)
			0x75, 0x06,
			// inc [pLapResetVal]
			0xFF, 0x05, arrLapResetValPtr[0], arrLapResetValPtr[1], arrLapResetValPtr[2], arrLapResetValPtr[3]
		}, 
		10);
	
#endregion

#region WATCHERS

	vars.mwPauseCalled = new MemoryWatcher<int>(pLoadScrVal);
	vars.mwLapCalled = new MemoryWatcher<int>(pLapFuncVal);
	vars.mwLapReset = new MemoryWatcher<int>(pLapResetVal);
	vars.mwLastLapTime = new MemoryWatcher<float>((IntPtr)0x511F00);
	vars.mwLapTimer = new MemoryWatcher<float>((IntPtr)0x511EF8);
	vars.mwLaps = new MemoryWatcher<int>((IntPtr)0x511F04);
	vars.mwMaxLaps = new MemoryWatcher<int>((IntPtr)0x521d54);
	vars.mwlWatchers = new MemoryWatcherList()
	{
		vars.mwPauseCalled,
		vars.mwLapCalled,
	};
	vars.mwlLapTimeWatchers = new MemoryWatcherList()
	{
		vars.mwLastLapTime,
		vars.mwLapReset,
		vars.mwLapTimer,
		vars.mwMaxLaps,
		vars.mwLaps

	};

#endregion

	Func<bool> IsNotInMap = () =>
	{
		return (vars.bLoading || current.pCamera == 0);	
	};
	vars.IsNotInMap = IsNotInMap;

	Func<bool> IsNotInRace = () => 
	{
		return (vars.IsNotInMap() 
		|| (current.pCamera != 0 
		&& (vars.mwLaps.Current == -1 || current.nRaceState < 3 || current.nRaceState == 6 
		|| (vars.mwLapTimer.Old == vars.mwLapTimer.Current && vars.mwLapTimer.Current == 0))));
	};
	vars.IsNotInRace = IsNotInRace;
	vars.oldCurTime = 0;
}

update
{
	
	vars.mwlWatchers.UpdateAll(game);

	if (vars.mwPauseCalled.Changed)
		vars.bLoading = true;

	if (old.pCamera == 0 && current.pCamera != 0)
		vars.bLoading = false;

	if (old.pLastFunc != 0x4fe788 && !vars.bLoading)
	{
		vars.mwlLapTimeWatchers.UpdateAll(game);

		bool inGame = !vars.IsNotInMap();
		bool timeMenu = settings["time-menu"] && !inGame;
		bool lapTimerPaused = vars.IsNotInRace();

		float delta = 0;
		float globalDelta = (current.nGlobalTimerTick - old.nGlobalTimerTick) * current.fRate;
		float lapDelta = vars.mwLapTimer.Current - vars.mwLapTimer.Old;

		// are we in a race?
		if (inGame)
		{
			// are we paused? if so make sure we count pause time
			if (!(current.bIsPaused && lapDelta == 0 && !settings["time-pauses"]))
				// is the lap timer paused?
				if (lapTimerPaused)
				{
					// if so and we aren't paused then make sure allow timing pre/post race
					if ((settings["time-prerace"] && current.nRaceState < 3) 
					&& (settings["time-postrace"] && current.nRaceState == 6))
						delta = globalDelta;
				}
				else
					// use the global timer if we're paused
					delta = (current.bIsPaused) ? globalDelta : lapDelta;
		}
		// if not make sure we allow timing menus
		else if (timeMenu)
			delta = globalDelta;

		if (delta < 0f)
			delta = vars.mwLapTimer.Current;
		
		// the lap time advances ever so slightly after the lap ends before it is reset
		// so we'll have to account for that
		// new current time = old current time - (lap timer before reset - last lap time) + lap timer now 
		bool lapAdvance = (vars.mwLaps.Current != vars.mwLaps.Old && vars.mwMaxLaps.Current > 0);
		bool lapLast = lapAdvance && vars.mwMaxLaps.Current == vars.mwLaps.Current;
		bool lapFirst = vars.mwMaxLaps.Current > 0 && vars.mwLaps.Current + 1 == 1;

		if (vars.mwLapReset.Changed)
		{
			delta = vars.mwLastLapTime.Current - vars.mwLapTimer.Old;
			vars.fCurTime += delta;

			vars.TimerModel.CurrentState.SetGameTime(TimeSpan.FromSeconds(vars.fCurTime));

			if ((settings["split-laps"] && !(settings["split-ignore1st"] && lapFirst)) 
			|| (settings["split-end"] && lapLast))
			{	
				vars.TimerModel.Split();
				vars.oldCurTime = vars.fCurTime;
			}

			if (settings["start-everylap"])
			{
				vars.TimerModel.Reset();
				vars.fCurTime = vars.mwLapTimer.Current;
				vars.TimerModel.Start();
				return;
			}

			vars.prints("TIMING", "Lap end at " + vars.mwLastLapTime.Current + ", " + delta + " off old lap time");
			vars.prints("TIMING", "Lap time current is " + vars.mwLapTimer.Current + " and old is " + vars.mwLapTimer.Old);
			if (!lapLast)
			{
				float oldCurTime = vars.fCurTime;
				vars.fCurTime += vars.mwLapTimer.Current;
				vars.prints("TIMING", "Adjusted timer: " + oldCurTime + " -> " + vars.fCurTime);
			}
		}
		else
			vars.fCurTime += delta > 0 ? delta : 0;

		//print(vars.mwLastLapTime.Current + " " + vars.mwLapTimer.Current + " " + vars.mwLapTimer.Old + " " + ((vars.fCurTime - vars.oldCurTime) - vars.mwLapTimer.Current) + " " + delta);
	}
}

split
{
	if (!settings["split"] || vars.IsNotInMap())
		return false;
	if (settings["split-gaincontrol"] && current.nRaceState == 3 && old.nRaceState == 2)
		return true;
	if (settings["split-checkpoint"] && !vars.IsNotInRace() && current.nCheckpoint > old.nCheckpoint)
		foreach (int x in vars.listCheckpointMod)
			if ((current.nCheckpoint % x == 0) && settings["split-checkpoint-every" + x])
				return true;
}

start
{
	vars.fCurTime = 0f;

	if (!settings["start"] || vars.IsNotInMap())
		return false;
	if (settings["start-gaincontrol"] && current.nRaceState == 3 && old.nRaceState == 2)
		return true;
	if (settings["start-lap"] && vars.mwLapCalled.Changed)
	{
		vars.fCurTime += vars.mwLapTimer.Current;
		return true;
	}
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
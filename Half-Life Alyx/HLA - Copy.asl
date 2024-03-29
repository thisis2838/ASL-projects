// HLVR AUTO SPLITTER 
// VERSION 2.5 -- JUNE 05 2021
// CREDITS: 
	// Lyfeless and DerkO for starting the project, initial load removal and splitting code
	// 2838 for Auto-Start, Auto-End, entity list and sigscanning shenanigans
// IF THIS SPLITTER BREAKS FOR YOU PLEASE DO MENTION IN #source2-general IN THE SOURCERUNS DISCORD (it's probably 2838's fault)

state("hlvr") { }

init
{
	// hla accesses static data not by using absolute pointers but using an offset off to the very next instruction instead
	// so we'll have to specify the size of the instruction
    Func<IntPtr, int, int, IntPtr> GetPointerFromOpcode = (ptr, trgOperandOffset, totalSize) =>
	{
		int offset = memory.ReadValue<int>(ptr + trgOperandOffset, 4);
		if (offset == 0)
			return IntPtr.Zero; 
		IntPtr actualPtr = IntPtr.Add((ptr + totalSize), offset);
		return actualPtr;
	};

	Action<IntPtr, string> ReportPointer = (ptr, name) => 
	{
		if (ptr == IntPtr.Zero)
			vars.print("[SIGSCANNING] " + name + " ptr was NOT found!!");
		else
			vars.print("[SIGSCANNING] " + name + " ptr was found at " + ptr.ToString("X"));
	};
	
#region SIGNATURE SCANNING
	vars.sigentList 	=	new SigScanTarget(6, 	"40 ?? 48 ?? ?? ??", 
													"48 ?? ?? ?? ?? ?? ??", // MOV RAX,qword ptr [DAT_1814e3bc0]
													"8b ?? 48 ?? ?? ?? ?? ?? ?? 48 ?? ?? ff ?? ?? ?? ?? ?? 4c ?? ??");
	vars.sigloading 	=	new SigScanTarget(18, 	"B2 01 C6 05 ?? ?? ?? ?? 01 48 8B 01 FF 90 ?? ?? ?? ??", 
													"C7 05 ?? ?? ?? ?? 01 00 00 00", // MOV dword ptr [DAT_180f67f7c],0x1 
													"0F 28 74 24 40 48 83 C4 50 5B");
	vars.siginLvlTrans 	=	new SigScanTarget(30, 	"F3 0F 11 05 ?? ?? ?? ?? E8 ?? ?? ?? ?? 48 8B 86 ?? ?? ?? ?? 48 8D 0D ?? ?? ?? ?? 48 85 C0",
													"C6 05 ?? ?? ?? ?? 01"); // MOV byte ptr [DAT_180e8916c],0x1)
	vars.sigbuildNum	=	new SigScanTarget(4,	"48 83 ec ??",
													"8b 05 ?? ?? ?? ??", // MOV EAX,dword ptr [0x18053ef54]
													"33 ff 85 c0 0f ?? ?? ?? ?? 00 48 89 5c 24 30 8b df 48 89 74 24 38");
	vars.sigmapTime		=	new SigScanTarget(11,	"F3 0F 58 ?? 48 8B 05 ?? ?? ?? ??",
													"F3 0F 11 ?? ?? ?? ?? ??", // this
													"48 85 C0 74 ?? 80 38 00 74 ??");
	vars.sigmapTimenoVr	=	new SigScanTarget(0,	"4C 8B 05 ?? ?? ?? ??", // MOV R8,qword ptr [0x18125f8e0]
													"48 8D 0D ?? ?? ?? ?? 48 8B 05 ?? ?? ?? ?? 41 B1 01");
	vars.sigmapName		=	new SigScanTarget(7,	"48 8B 97 ?? ?? ?? ??", 
													"48 8D 0D ?? ?? ?? ??", // LEA RCX,[0x180544a00]
													"48 8B 5C 24 ??");
	vars.signoVr		=	new SigScanTarget(0,	"48 8B 0D ?? ?? ?? ??", // MOV RCX,qword ptr [0x180e5e928]
													"48 8B DA 48 85 C9 0F 84 ?? ?? ?? ?? 48 8B 01");
	vars.sigSignOnState	=	new SigScanTarget(0,	"48 8B 05 ?? ?? ?? ??", // MOV RAX,qword ptr [signOnState base]
													"48 8B D9 48 8D 0D ?? ?? ?? ?? FF 90 ?? ?? ?? ?? 48 85 C0 74 ?? 4C 8B 00");

	var profiler = Stopwatch.StartNew();
	
	// 2838: init process scanners (looks ugly but makes it so it doesn't take 10 seconds to scan)
	ProcessModuleWow64Safe client = modules.FirstOrDefault(x => x.ModuleName.ToLower() == "client.dll");
	ProcessModuleWow64Safe server = modules.FirstOrDefault(x => x.ModuleName.ToLower() == "server.dll");
	ProcessModuleWow64Safe engine = modules.FirstOrDefault(x => x.ModuleName.ToLower() == "engine2.dll");
	if (client == null || engine == null || server == null)
	{
		Thread.Sleep(1000);
		vars.print("[SIGSCANNING] All modules aren't yet loaded! Waiting 1 second until next try");
        throw new Exception();
	}
	var clientScanner = new SignatureScanner(game, client.BaseAddress, client.ModuleMemorySize);
	var engineScanner = new SignatureScanner(game, engine.BaseAddress, engine.ModuleMemorySize);
	var serverScanner = new SignatureScanner(game, server.BaseAddress, server.ModuleMemorySize);

	IntPtr ptrnoVr			= GetPointerFromOpcode(clientScanner.Scan(vars.signoVr), 3, 7);
	// this pointer doesn't seem to be initialized whenever the game is in novr
	bool isnoVr = new DeepPointer(ptrnoVr).Deref<IntPtr>(game) == IntPtr.Zero;
	
	IntPtr ptrentList 		= GetPointerFromOpcode(serverScanner.Scan(vars.sigentList), 3, 7);
	IntPtr ptrloading		= GetPointerFromOpcode(clientScanner.Scan(vars.sigloading), 2, 10); 
	IntPtr ptrinLvlTrans	= GetPointerFromOpcode(clientScanner.Scan(vars.siginLvlTrans), 2, 7);
	IntPtr ptrbuildNum		= GetPointerFromOpcode(engineScanner.Scan(vars.sigbuildNum), 2, 6);
	IntPtr ptrmapTime 		= (isnoVr) ? GetPointerFromOpcode(serverScanner.Scan(vars.sigmapTimenoVr), 3, 7) : GetPointerFromOpcode(clientScanner.Scan(vars.sigmapTime), 4, 8);
	IntPtr ptrmapName 		= GetPointerFromOpcode(engineScanner.Scan(vars.sigmapName), 3, 7) + 0x100;
	IntPtr ptrSignOnState	= GetPointerFromOpcode(engineScanner.Scan(vars.sigSignOnState), 3, 7) + 0x218;
	
	ReportPointer(ptrentList, "entList");
	ReportPointer(ptrinLvlTrans, "inLvlTrans");
	ReportPointer(ptrbuildNum, "buildNum");
	ReportPointer(ptrloading, "loading");
	ReportPointer(ptrmapTime, "mapTime");
	ReportPointer(ptrmapName, "mapName");
	ReportPointer(ptrnoVr, "noVr");
	ReportPointer(ptrSignOnState, "signOnState base");

#region ACHIEVEMENT FUNCTION INJECTION

	IntPtr achievePtrLoc = IntPtr.Zero;
	vars.achieveJmpInscPtr = IntPtr.Zero;
	vars.achievePtrLoc = IntPtr.Zero;

	// find cvar string pointer, the cvar in particular is stat_tracker_dump_stats, a non-functional / disabled command
	var serverTmpScanner = new SignatureScanner(game, server.BaseAddress, server.ModuleMemorySize);
	var stringTarget = new SigScanTarget("737461745F747261636B65725F64756D705F7374617473");
	IntPtr stringPtr = serverScanner.Scan(stringTarget);
	ReportPointer(stringPtr, "achievement stuff - string ptr");
	if (stringPtr == IntPtr.Zero)
		goto skipachieve;

	// find the reference to that string
	var stringRef = new SigScanTarget(7, "4C 8D 05 ?? ?? ?? ?? 48 8D 15 ?? ?? ?? ?? 48 8D 0D ?? ?? ?? ??");
	bool found = false;
	int size = server.ModuleMemorySize;
	IntPtr serverEndPtr = server.BaseAddress + server.ModuleMemorySize;
	IntPtr d = IntPtr.Zero;
	while (!found)
	{
		stringRef.OnFound = (f_proc, f_scanner, f_ptr) =>
		{
			if (GetPointerFromOpcode(f_ptr, 3, 7) == stringPtr)
				found = true;
			return f_ptr;
		};
		d = serverTmpScanner.Scan(stringRef);
		size = (int)((long)serverEndPtr - (long)d - 0x1);
		if (size <= 20)
			break;
		serverTmpScanner = new SignatureScanner(game, d + 0x1, size);
	}
	// from there get its data field and use that as the base for injecting new code
	IntPtr begin = GetPointerFromOpcode(d + 0x7, 3, 7);
	ReportPointer(begin, "achievement stuff - injection begin");
	if (begin == IntPtr.Zero)
		goto skipachieve;

	// find the instruction at the beginning of the function which handles achievements
	var instructionTarget = new SigScanTarget("FF 50 ?? 84 C0 0F 85 ?? ?? ?? ?? 48 8B 03");
	IntPtr orig1 = serverScanner.Scan(instructionTarget);
	ReportPointer(orig1, "achievement stuff - first instruction location");
	if (orig1 == IntPtr.Zero)
		goto skipachieve;
	IntPtr orig2 = orig1 + 0x5;
	vars.achieveJmpInscPtr = orig1;

	// begin assembling commands
	// determine pointer for each command
	achievePtrLoc = begin;
	IntPtr in1 = begin + 0x8;
	IntPtr in2 = in1 + 0x7;
	IntPtr in3 = in2 + 0x3;
	IntPtr in4 = in3 + 0x2;
	
	// figure out offsets for the asm instructions
	// offset between stored pointer location and first instruction, should always be 8
	int off1 = (int)((long)achievePtrLoc - (long)in2);
	byte[] off1bytes = BitConverter.GetBytes(off1);
	// offset for the jump from the end of our injected code back to the original function
	int off2 = (int)((long)orig2 - (long)(in4 + 0x5));
	byte[] off2bytes = BitConverter.GetBytes(off2);
	// offset for the jump from the original function to our injected code
	int off3 = (int)((long)in1 - (long)(orig1 + 0x5));
	byte[] off3bytes = BitConverter.GetBytes(off3);

	// prepare byte arrays for writing 
	// mov [achievePtrLoc],rcx
	byte[] first = new byte[] { 0x48, 0x89, 0x0D, off1bytes[0], off1bytes[1], off1bytes[2], off1bytes[3] };
	// call qword ptr [rax+28]
	byte[] second = new byte[] { 0xFF, 0x50, 0x28 };
	// test al, al
	byte[] third = new byte[] { 0x84, 0xc0 };
	// jump orig2
	byte[] fourth = new byte[] { 0xe9, off2bytes[0], off2bytes[1], off2bytes[2], off2bytes[3] };
	// jump in1
	byte[] jmp = new byte[] { 0xe9, off3bytes[0], off3bytes[1], off3bytes[2], off3bytes[3] };

	// store original bytes
	vars.achieveOrigBytes1 = memory.ReadBytes(orig1, 5);
	vars.achieveOrigBytes2 = memory.ReadBytes(begin, 55);
	
	// write operations
	game.VirtualProtect((IntPtr)begin, (int)128, MemPageProtect.PAGE_EXECUTE_READWRITE);
	game.VirtualProtect((IntPtr)orig1, (int)10, MemPageProtect.PAGE_EXECUTE_READWRITE);
	memory.WriteBytes(in1, first);
	memory.WriteBytes(in2, second);
	memory.WriteBytes(in3, third);
	memory.WriteBytes(in4, fourth);
	memory.WriteBytes(orig1, jmp);

	memory.WriteBytes(achievePtrLoc, BitConverter.GetBytes(0xFFFFFFFFFFFFFFFF));

	goto complete;

#endregion

skipachieve:
	vars.print("Achievement splitting code failed!");

complete:
	vars.achievePtrLoc = achievePtrLoc;
	profiler.Stop();
	vars.print("[SIGSCANNING] Signature scanning done in " + profiler.ElapsedMilliseconds * 0.001f + " seconds");

#endregion

	int buildnum = memory.ReadValue<int>(ptrbuildNum);
	vars.print("[GAME INFO] Game is build number " + buildnum);	
	vars.print("[GAME INFO] Game is running in " + ((isnoVr) ? "No VR" : "VR") + " mode");
	
#region SETTING UP WATCHLIST
	// 2838: some of these offsets should be sigscanned...
	vars.loading 		= new MemoryWatcher<int>(ptrloading);
	vars.mapTime 		= (isnoVr) ? new MemoryWatcher<float>(new DeepPointer(ptrmapTime, 0x0)) : new MemoryWatcher<float>(ptrmapTime);
	vars.inLvlTrans 	= new MemoryWatcher<byte>(ptrinLvlTrans);
	vars.entList		= new MemoryWatcher<IntPtr>(new DeepPointer(ptrentList));
	vars.moveFlag 		= new MemoryWatcher<byte>(new DeepPointer(ptrentList, 0x18, 0x78, 0x2e9c));
	vars.map			= new StringWatcher(ptrmapName, 120);
	vars.signOnState	= new MemoryWatcher<byte>(new DeepPointer(ptrSignOnState, 0x1e0, 0x0, 0x50));
	vars.accumTime		= new MemoryWatcher<int>(new DeepPointer(ptrentList, 0x20b8, 0x68));
	vars.achievePtr		= new MemoryWatcher<IntPtr>(vars.achievePtrLoc);
	
	vars.watchIt = new MemoryWatcherList() {
		vars.loading,
		vars.mapTime,
		vars.inLvlTrans,
		vars.entList,
		vars.moveFlag,
		vars.map,
		vars.signOnState,
		vars.accumTime,
		vars.achievePtr
	};
#endregion
	
#region ENTITY LIST FUNCTIONS
	
	const int entInfoSize = 120;
	
	Func<int, IntPtr> GetEntPtrFromIndex = (index) =>
	{
		// the game splits the entity pointer list into blocks with seemingly a certain size
		// this function is taken from the game's decompiled code

		int block = 24 + (index >> 9) * 8;
		int pos = (index & 511) * entInfoSize;
		
		DeepPointer DPentPtr = new DeepPointer(vars.entList.Current + block, 0x0);
		IntPtr blockPtr = IntPtr.Zero;
		DPentPtr.DerefOffsets(game, out blockPtr);
		
		IntPtr entPtr = blockPtr + pos;
		return entPtr;
	};
	
	Func<IntPtr, bool, string> GetNameFromPtr = (entPtr, isTargetName) =>
	{
		DeepPointer nameptr = new DeepPointer(entPtr, 0x10, (isTargetName) ? 0x18 : 0x20, 0x0);
		string name = "";
		nameptr.DerefString(game, 128, out name);
		return name;
	};
	
	// 2838: EXTREMELY expensive, do NOT call frequently!!!!
	Func<string, bool, IntPtr> GetEntFromName = (name, isTargetName) =>
	{
		var prof = Stopwatch.StartNew();
		// 2838: theorectically the index can go all the way up to 32768 but it never does even on the biggest of maps
		for (int i = 0; i <= 20000; i++)
		{
			IntPtr entPtr = GetEntPtrFromIndex(i);
			if (entPtr != IntPtr.Zero)
			{
				if (GetNameFromPtr(entPtr, isTargetName) == name)
				{
					prof.Stop();
					vars.print("[ENTFINDING] Successfully found " + name + "'s pointer after " + prof.ElapsedMilliseconds * 0.001f + " seconds, index #" + i);
					return entPtr;
				}
				else continue;
			}
			prof.Stop();
			vars.print("[ENTFINDING] Can't find " + name + "'s pointer! Time spent: " + prof.ElapsedMilliseconds * 0.001f + " seconds");
		}
		
		return IntPtr.Zero;
	};
	
	// 2838: not a necessary function but imma just put this here in case someone finds a use for it
	Func<IntPtr, string> printPosFromPtr = (entPtr) =>
	{
		DeepPointer posDP = new DeepPointer(entPtr, 0x1a0, 0x108);
		IntPtr posPtr;
		posDP.DerefOffsets(game, out posPtr);
		float xPos; memory.ReadValue<float>(posPtr, out xPos);
		float yPos; memory.ReadValue<float>(posPtr + 0x4, out yPos);
		float zPos; memory.ReadValue<float>(posPtr + 0x8, out zPos);
		
		string pos = xPos + " " + yPos + " " + zPos;
		
		return pos;
	};
	
	vars.GetEntFromName = GetEntFromName;
	vars.GetEntPtrFromIndex = GetEntPtrFromIndex;
	vars.GetNameFromPtr = GetNameFromPtr;
	vars.printPosFromPtr = printPosFromPtr;	
#endregion

	vars.OnSessionStart();
}

startup
{
    //SETTINGS
    settings.Add("chapters", false, "Split on Chapters");
	settings.SetToolTip("chapters", "Split on Chapter Transitions Instead of Per-Map");
    
    settings.Add("il", false, "IL Mode");
	settings.SetToolTip("il", "Only used when running ILs. Starts automatically on any map selected");

	settings.Add("changelevelsplit", true, "Use new method of splitting");
	settings.SetToolTip("changelevelsplit", "Splits on detected game changelevel, works with campaign mods that change maps through changelevel triggers");

	settings.Add("achievementsplit", false, "Split on getting achievements");
	settings.SetToolTip("achievementsplit", "Splits on obtaining an achievement, duplicates included");

    //MAP DATA
	vars.visitedMaps = new List<string>();
    
    vars.maps = new Dictionary<string, Tuple<int, int>>() { 
    //   MAP NAME                                             ID          CHAPTER
        {"a1_intro_world"               , new Tuple<int, int>(0         , 0         )},
        {"a1_intro_world_2"             , new Tuple<int, int>(1         , 0         )},
        
        {"a2_quarantine_entrance"       , new Tuple<int, int>(2         , 1         )},
        {"a2_pistol"                    , new Tuple<int, int>(3         , 1         )},
        {"a2_hideout"                   , new Tuple<int, int>(4         , 1         )},
        
        {"a2_headcrabs_tunnel"          , new Tuple<int, int>(5         , 2         )},
        {"a2_drainage"                  , new Tuple<int, int>(6         , 2         )},
        {"a2_train_yard"                , new Tuple<int, int>(7         , 2         )},
        
        {"a3_station_street"            , new Tuple<int, int>(8         , 3         )},
        
        {"a3_hotel_lobby_basement"      , new Tuple<int, int>(9         , 4         )},
        {"a3_hotel_underground_pit"     , new Tuple<int, int>(10        , 4         )},
        {"a3_hotel_interior_rooftop"    , new Tuple<int, int>(11        , 4         )},
        {"a3_hotel_street"              , new Tuple<int, int>(12        , 4         )},
        
        {"a3_c17_processing_plant"      , new Tuple<int, int>(13        , 5         )},
        
        {"a3_distillery"                , new Tuple<int, int>(14        , 6         )},
        
        {"a4_c17_zoo"                   , new Tuple<int, int>(15        , 7         )},
        
        {"a4_c17_tanker_yard"           , new Tuple<int, int>(16        , 8         )},
        
        {"a4_c17_water_tower"           , new Tuple<int, int>(17        , 9         )},
        {"a4_c17_parking_garage"        , new Tuple<int, int>(18        , 9         )},
        
        {"a5_vault"                     , new Tuple<int, int>(19        , 10        )},
        {"a5_ending"                    , new Tuple<int, int>(20        , 10        )},
        
        {"startup"                      , new Tuple<int, int>(-10       , -10       )}
    };
	
	vars.signOnStates = new Dictionary<int, string>() 
	{
	//	SIGN ON STATE		NAME
		{0,					"None"},
		{1,					"Challenge"},
		{2,					"Connected"},
		{3,					"New"},
		{4,					"Prespawn"},
		{5,					"Spawn"},
		{6,					"Full"},
		{7,					"ChangeLevel"},
	};
    
    vars.waitForLoading = false;
    
    //TIMER
    vars.currentTime = 0.0f;
	vars.mapStart = false;
	
	//END STUFF 
	vars.autoGripDP1 = new MemoryWatcher<byte>(IntPtr.Zero);
	vars.autoGripDP2 = new MemoryWatcher<byte>(IntPtr.Zero);

	Action OnSessionStart = () => {
		vars.print("[GAMESTATE] Session began at " + vars.PrintTimeInfo());

		if (vars.map.Current == "a5_ending")
		{
			// do both hands to really make sure we don't miss
			vars.autoGripDP1 = new MemoryWatcher<byte>(new DeepPointer(vars.GetEntFromName("g_release_hand1", true), 0x878, 0xb4));
			vars.autoGripDP2 = new MemoryWatcher<byte>(new DeepPointer(vars.GetEntFromName("g_release_hand2", true), 0x878, 0xb4));
		}
	};

	Action OnSessionEnd = () => {
		vars.print("[GAMESTATE] Session ended at " + vars.PrintTimeInfo());
		
		if (vars.map.Current == "a5_ending")
		{
			vars.autoGripDP1 = new MemoryWatcher<byte>(IntPtr.Zero);
			vars.autoGripDP2 = new MemoryWatcher<byte>(IntPtr.Zero);
		}
		vars.mapStart = false;
	};

	Action<string> prints = (msg) =>
	{
		print("[ALYX ASL] " + msg);
	};

	Func<string> PrintTimeInfo = () => 
	{
		return vars.currentTime + " timer time, " + vars.mapTime.Current + " internal time & " + vars.accumTime.Current + " save file time";
	};

	vars.print = prints;
	vars.PrintTimeInfo = PrintTimeInfo;

	vars.OnSessionStart = OnSessionStart;
	vars.OnSessionEnd = OnSessionEnd;

	vars.TimerStartHandler = (EventHandler)((s, e) => {
    	vars.print("[TIMER] Timer began at " + vars.PrintTimeInfo());

		if (vars.map.Current == "a5_ending")
		{
			// do both hands to really make sure we don't miss
			vars.autoGripDP1 = new MemoryWatcher<byte>(new DeepPointer(vars.GetEntFromName("g_release_hand1", true), 0x878, 0xb4));
			vars.autoGripDP2 = new MemoryWatcher<byte>(new DeepPointer(vars.GetEntFromName("g_release_hand2", true), 0x878, 0xb4));
		}
    });

	vars.TimerSplitHandler = (EventHandler)((s, e) => {
		vars.print("[TIMER] Timer split at " + vars.PrintTimeInfo());
	});

	timer.OnStart += vars.TimerStartHandler;
	timer.OnSplit += vars.TimerSplitHandler;

	// ACHIEVEMENT CODE
	vars.achieveOrigBytes1 = new byte[5];
	vars.achieveOrigBytes2 = new byte[55];
	vars.achieveBrokenBottles = 0;
	vars.obtainedAchievements = new List<string>();
}

update
{
	vars.watchIt.UpdateAll(game);

	if (vars.signOnState.Changed)
	{
		vars.print("[GAMESTATE] Game state changed from " + vars.signOnStates[vars.signOnState.Old] + " to " + vars.signOnStates[vars.signOnState.Current]);
		if (vars.signOnState.Current == 6)
			vars.OnSessionStart();
		else if (vars.signOnState.Old == 6)
			vars.OnSessionEnd();
	}

	if (vars.map.Changed)
		vars.print("[GAMESTATE] Map changed from " + vars.map.Old + " to " + vars.map.Current);
	
	if (vars.map.Current == "a5_ending")
	{
		vars.autoGripDP1.Update(game);
		vars.autoGripDP2.Update(game);
	}
	
	// 2838: 
	// the game has 2 states of loading: waiting for map load (state 1) and waiting for the player to press the trigger (state 2)
	// we'll only need to exclude state 1 as state 2 is when the game has finished loading in
	
	float delta = vars.mapTime.Current - vars.mapTime.Old;
	
	if (delta > 0.0f && vars.loading.Current != 1 && vars.inLvlTrans.Current == 0)
		vars.currentTime += delta;
}

start
{   
	vars.currentTime = 0.0f;
	vars.achieveBrokenBottles = 0;
	vars.visitedMaps.Clear();
	vars.obtainedAchievements.Clear();

    //Normal Start Condition

    if (vars.map.Current == "a1_intro_world") {
        return (vars.moveFlag.Current == 0 && vars.moveFlag.Old == 1);
    }
    else if ((vars.map.Current != "startup") && settings["il"])
	{
		if (vars.mapStart)
		{
			if (vars.loading.Changed && vars.loading.Old == 2 && vars.loading.Current != 1)
			{
				vars.mapStart = false;
				vars.print("[TIMER] IL splitting enabled, starting from unpause");
				return true;
			}
			return false;
		}
		vars.mapStart = (vars.signOnState.Changed && vars.signOnState.Current == 4 && vars.accumTime.Current == 0);

		return false;
	}
}

reset
{
	vars.visitedMaps.Clear();

	if ((vars.map.Current != "startup" && vars.map.Current != "a1_intro_world") && settings["il"] )
	{
		vars.mapStart = (vars.signOnState.Changed && vars.signOnState.Current == 4 && vars.accumTime.Current == 0);
		return vars.mapStart;
	}
	else if (vars.map.Current == "a1_intro_world")
    {
		if (vars.moveFlag.Old == 0 && vars.moveFlag.Current == 1) 
		{
			vars.currentTime = 0.0f;
			return true;
        } 
		return false;
    }
}

split
{
    //Ending Conditional
	if (vars.map.Current == "a5_ending" && vars.loading.Current == 0)
	{
        return (vars.autoGripDP1.Current == 0 && vars.autoGripDP1.Old == 1) 
		|| (vars.autoGripDP2.Current == 0 && vars.autoGripDP2.Old == 1);
	}

	if (settings["changelevelsplit"])
	{
		if (vars.signOnState.Current == 7)
		{
			if (vars.map.Changed && vars.map.Current != "startup" 
			&& !vars.visitedMaps.Contains(vars.map.Current))
			{
				vars.visitedMaps.Add(vars.map.Current);
				vars.print("[GAMESTATE] Map changelevel event from " + vars.map.Old + " to " + vars.map.Current);

				if (settings["chapters"] && vars.maps[vars.map.Current.ToLower()].Item2 == vars.maps[vars.map.Old.ToLower()].Item2 + 1)
				{
					vars.print("[GAMESTATE] Chapter change!");
					return true;
				}
				else return (!settings["chapters"]);
			}
		}

		// HACKHACK: intro_world_2 is transitioned from a generic map command, so just add an edge case here
		if (vars.map.Old == "a1_intro_world" && vars.map.Current == "a1_intro_world_2")
		{
			vars.visitedMaps.Add(vars.map.Current);
			return true;
		}
	}
	//Only split if map is increasing
    else 
	{
		if (!settings["chapters"]) 
			return (vars.maps[vars.map.Current.ToLower()].Item1 == vars.maps[vars.map.Old.ToLower()].Item1 + 1);
		else return vars.maps[vars.map.Current.ToLower()].Item2 == vars.maps[vars.map.Old.ToLower()].Item2 + 1;
	} 

	if (vars.achievePtrLoc != IntPtr.Zero)
	{
		if (memory.ReadValue<ulong>((IntPtr)vars.achievePtrLoc) != 0xFFFFFFFFFFFFFFFF)
		{
			IntPtr stringPtr; 
			new DeepPointer((IntPtr)vars.achievePtrLoc, 0x8, 0x0).DerefOffsets(game, out stringPtr);
			string achievement = memory.ReadString(stringPtr, 256);
			try
			{
				if (!vars.obtainedAchievements.Contains(achievement))
				{
					vars.print("[ACHIEVEMENTS] Got achievement " + achievement);
					if (achievement.Contains("GLOBAL"))
					{
						if (achievement == "SIDE_GLOBAL_BREAK_BOTTLES")
						{
							vars.achieveBrokenBottles++;
							vars.print("[ACHIEVEMENTS] Mazel Tov progress: " + vars.achieveBrokenBottles + " / 50");
							if (vars.achieveBrokenBottles < 50)
								return false;
						}
					}	
					vars.obtainedAchievements.Add(achievement);
					return settings["achievementsplit"];
				}
			}
			finally
			{
				memory.WriteBytes((IntPtr)vars.achievePtrLoc, BitConverter.GetBytes(0xFFFFFFFFFFFFFFFF));
			}
		}
	}
	
}

isLoading { return true; }

shutdown {
    timer.OnStart -= vars.TimerStartHandler;
    timer.OnSplit -= vars.TimerSplitHandler;

	if (vars.achieveJmpInscPtr != IntPtr.Zero && vars.achievePtrLoc != IntPtr.Zero) 
	{
		memory.WriteBytes((IntPtr)vars.achieveJmpInscPtr, (byte[])vars.achieveOrigBytes1);
		memory.WriteBytes((IntPtr)vars.achievePtrLoc, (byte[])vars.achieveOrigBytes2);
	}

	vars.print("Exiting");
}

gameTime { return TimeSpan.FromSeconds(vars.currentTime); }
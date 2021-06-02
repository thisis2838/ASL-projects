// SYNERGY AUTOSPLITTER
// CREDITS:
// - SmileyAG for basic sigscanning functionality
// - ScriptedSnark for initial splitter codework
// HOW TO USE: https://github.com/ScriptedSnark/Synergy-Autosplitter/blob/main/README.md
// PLEASE REPORT THE PROBLEMS TO EITHER THE ISSUES SECTION IN THE GITHUB REPOSITORY ABOVE

state("synergy") {}

startup
{
    settings.Add("AutostartILs", false, "Autostart for ILs");

    vars.startmaps = new List<string>() 
    {"d1_trainstation_01", "ep1_citadel_00", "ep2_outland_01"};

    vars.aslVersion = "2021/06/02";


    Action<string, string> printTag = (msg, tag) =>
    {
        print("[SYNERGY ASL] [" + tag + "] " + msg);
    };

    Action<IntPtr, string> ReportPointer = (ptr, name) => 
    {
        if (ptr == IntPtr.Zero)
            printTag(name + " wasn't found!", "SIGSCANNING");
        else
            printTag(name + " found at 0x" + ptr.ToString("X"), "SIGSCANNING");
    };

    vars.ReportPointer = ReportPointer;
    vars.printTag = printTag;

    Dictionary<int, string> serverStates = new Dictionary<int, string>()
    {
        {0,     "Dead"},
        {1,     "Loading"},
        {2,     "Active"},
        {3,     "Paused"},
    };

    Dictionary<int, string> signOnStates = new Dictionary<int, string>()
    {
        {0,     "None"},
        {1,     "Challenge"},
        {2,     "Connected"},
        {3,     "New"},
        {4,     "PreSpawn"},
        {5,     "Spawn"},
        {6,     "Full"},
        {7,     "ChangeLevel"},
    };

    Dictionary<int, string> hostStates = new Dictionary<int, string>()
    {
        {0,     "NewGame"},
        {1,     "LoadGame"},
        {2,     "ChangeLevelSP"},
        {3,     "ChangeLevelMP"},
        {4,     "Run"},
        {5,     "GameShutdown"},
        {6,     "Shutdown"},
        {7,     "Restart"},
    };

    Func<int, string> EvaluateServerState = (state) =>
    {
        return serverStates[state];
    };

    Func<int, string> EvaluateSignOnState = (state) =>
    {
        return signOnStates[state];
    };

    Func<int, string> EvaluateHostState = (state) =>
    {
        return hostStates[state];
    };

    vars.EvaluateServerState = EvaluateServerState;
    vars.EvaluateSignOnState = EvaluateSignOnState;
    vars.EvaluateHostState = EvaluateHostState;
}

init
{
    print("=========+++=========");
    print("SYNERGY AUTOSPLITTER VERSION " + vars.aslVersion + " by SmileyAG, ScriptedSnark and 2838");
    print("=========+++=========");

#region SIGSCANNING

    ProcessModuleWow64Safe engine = modules.FirstOrDefault(x => x.ModuleName.ToLower() == "engine.dll");
    ProcessModuleWow64Safe server = modules.FirstOrDefault(x => x.ModuleName.ToLower() == "server.dll");
    if (engine == null || server == null)
    {
        Thread.Sleep(1000);
        print("All modules not yet loaded!");
            throw new Exception();
    }
    
    var engineScanner = new SignatureScanner(game, engine.BaseAddress, engine.ModuleMemorySize);
    var serverScanner = new SignatureScanner(game, server.BaseAddress, server.ModuleMemorySize);
    
    var sig_serverState = new SigScanTarget(22, "83 F8 01 0F 8C ?? ?? 00 00 3D 00 02 00 00 0F 8F ?? ?? 00 00 83 3D ?? ?? ?? ?? 02 7D"); // https://github.com/fatalis/SourceSplit/blob/1056cc59c662e3cb7d77e64aef8bbc26c1e90061/GameMemory.cs#L63-L74
    var sig_mapName = new SigScanTarget(13, "D9 ?? 2C D9 C9 DF F1 DD D8 76 ?? 80 ?? ?? ?? ?? ?? 00"); // https://github.com/fatalis/SourceSplit/blob/1056cc59c662e3cb7d77e64aef8bbc26c1e90061/GameMemory.cs#L193-L201
    var sig_globalEntityListTarget = new SigScanTarget(8,
        "6A 00",                   // push    0
        "6A 00",                   // push    0
        "50",                      // push    eax
        "6A 00",                   // push    0
        "B9 ?? ?? ?? ??",          // mov     ecx, offset CGlobalEntityList_vtable_ptr
        "E8");                     // call    sub_22289800
    var sig_signonStateTarget = new SigScanTarget(17,
        "80 3D ?? ?? ?? ?? 00",    // cmp     byte_698EE114, 0
        "74 06",                   // jz      short loc_6936C8FF
        "B8 ?? ?? ?? ??",          // mov     eax, offset aDedicatedServe ; "Dedicated Server"
        "C3",                      // retn
        "83 3D ?? ?? ?? ?? 02",    // cmp     CBaseClientState__m_nSignonState, 2
        "B8 ?? ?? ?? ??");
    var sig_hostStateTarget = new SigScanTarget(2,
        "C7 05 ?? ?? ?? ?? 07 00 00 00", // mov     g_HostState_m_nextState, 7
        "C3");
    
    sig_hostStateTarget.OnFound = (proc, scanner, ptr) => proc.ReadPointer(ptr, out ptr) ? ptr - 4 : IntPtr.Zero;
    sig_signonStateTarget.OnFound = (proc, scanner, ptr) => proc.ReadPointer(ptr, out ptr) ? ptr : IntPtr.Zero;
    sig_globalEntityListTarget.OnFound = (proc, scanner, ptr) => proc.ReadPointer(ptr, out ptr) ? ptr + 4 : IntPtr.Zero;
    sig_serverState.OnFound = (proc, scanner, ptr) => !proc.ReadPointer(ptr, out ptr) ? IntPtr.Zero : ptr;
    sig_mapName.OnFound = (proc, scanner, ptr) => !proc.ReadPointer(ptr, out ptr) ? IntPtr.Zero : ptr;

    IntPtr ptr_serverState = engineScanner.Scan(sig_serverState);
    vars.ReportPointer(ptr_serverState, "server state");
    IntPtr ptr_mapName = engineScanner.Scan(sig_mapName);
    vars.ReportPointer(ptr_mapName, "map name");
    IntPtr ptr_entList = serverScanner.Scan(sig_globalEntityListTarget);
    vars.ReportPointer(ptr_entList, "entity list");
    IntPtr ptr_signOnState = engineScanner.Scan(sig_signonStateTarget);
    vars.ReportPointer(ptr_signOnState, "sign on state");
    IntPtr ptr_hostState = engineScanner.Scan(sig_hostStateTarget);
    vars.ReportPointer(ptr_hostState, "host state");

#endregion

#region ENTITY LIST FUNCTIONS

    // FUNCTIONS TAKEN FROM SOURCESPLIT -- CREDIT TO 2838, JUKSPA AND FATALIS

    Func<string, SignatureScanner, int> GetBaseEntityMemberOffset = (member, scanner) =>
    {
        int offset = -1;
        try
        {
            IntPtr stringPtr = scanner.Scan(new SigScanTarget(0, Encoding.ASCII.GetBytes(member)));
            if (stringPtr == IntPtr.Zero)
                return offset;

            var b = BitConverter.GetBytes(stringPtr.ToInt32());

            var target = new SigScanTarget(10, "C7 05 ?? ?? ?? ??" + BitConverter.ToString(b).Replace("-", " ")); // mov     dword_15E2BF1C, offset aM_fflags ; "m_fFlags"
            target.OnFound = (proc, s, ptr) => 
            {
                // this instruction is almost always directly after above one, but there are a few cases where it isn't
                // so we have to scan down and find it
                var proximityScanner = new SignatureScanner(proc, ptr, 256);
                return proximityScanner.Scan(new SigScanTarget(6, "C7 05 ?? ?? ?? ?? ?? ?? 00 00"));         // mov     dword_15E2BF20, 0CCh
            };

            IntPtr addr = scanner.Scan(target);
            game.ReadValue(addr, out offset);

            return offset;
        }
        finally
        {
            vars.printTag(member + "offset is 0x" + offset.ToString("X"), "SIGSCANNING");
        }
    };

    const int ENT_INFO_SIZE = 4 * 4;
    const int MAX_ENTS = 2048; // maybe higher?
    int ENT_NAME_OFFSET = GetBaseEntityMemberOffset("m_iName", serverScanner);
    int ENT_ABS_ORIGIN_OFFSET = GetBaseEntityMemberOffset("m_vecAbsOrigin", serverScanner);
    const int NEXT_ENT_PTR = 0xC;

    Func<int, IntPtr> GetEntInfoFromIndex = (index) =>
    {
        return (index < 0) ? IntPtr.Zero : ptr_entList + index * ENT_INFO_SIZE;
    };

    Func<int, IntPtr> GetEntPtrFromIndex = (index) =>
    {
        return game.ReadPointer(GetEntInfoFromIndex(index));
    };

    Func<string, int> GetEntIndexByName = (name) =>
    {
        for (int i = 0; i < MAX_ENTS; i++)
        {
            IntPtr entPtr = GetEntPtrFromIndex(i);
            if (entPtr == IntPtr.Zero)
                continue;

            IntPtr namePtr;
            game.ReadPointer(entPtr + ENT_NAME_OFFSET, false, out namePtr);
            if (namePtr == IntPtr.Zero)
                continue;

            string n;
            game.ReadString(namePtr, ReadStringType.ASCII, 32, out n);  // TODO: find real max len
            //print(namePtr.ToString("X"));
            if (n == name)
                return i;
        }

        return -1;
    };

    // note: this allows getting the pointers of entities that aren't networked over the client
    // and as such doesn't have an entindex (logic_relay, math_counter, etc..)
    Func<string, IntPtr> GetEntPtrFromName = (name) =>
    {
        IntPtr nextPtr = GetEntInfoFromIndex(0);
        do
        {
            if (nextPtr == IntPtr.Zero)
                return IntPtr.Zero;
            IntPtr namePtr;
            game.ReadPointer(game.ReadPointer(nextPtr) + ENT_NAME_OFFSET, false, out namePtr);
            if (namePtr != IntPtr.Zero)
            {
                string n;
                game.ReadString(namePtr, ReadStringType.ASCII, 32, out n);  // TODO: find real max len
                if (n == name)
                    return nextPtr;
            }
            nextPtr = game.ReadPointer(nextPtr + NEXT_ENT_PTR);
        }
        while (nextPtr != IntPtr.Zero);
        return IntPtr.Zero;
    };

    Func<float, float, float, float, bool, int> GetEntIndexByPos = (x, y, z, d, xy) =>
    {
        Vector3f pos = new Vector3f(x, y, z);

        for (int i = 0; i < MAX_ENTS; i++)
        {
            IntPtr info = GetEntPtrFromIndex(i);
            if (info == IntPtr.Zero)
                continue;

            Vector3f newpos;
            if (!game.ReadValue(info + ENT_ABS_ORIGIN_OFFSET, out newpos))
                continue;

            if (d == 0f)
            {
                if (newpos.BitEquals(pos) && i != 1) //not equal 1 becase the player might be in the same exact position
                    return i;
            }
            else // check for distance if it's a non-static entity like an npc or a prop
            {
                if (xy) 
                {
                    if (newpos.DistanceXY(pos) <= d && i != 1) 
                        return i;
                }
                else
                {
                    if (newpos.Distance(pos) <= d && i != 1) 
                        return i;
                }
            }
        }
        return -1;
    };

    vars.GetEntPtrFromIndex = GetEntPtrFromIndex;
    vars.GetEntIndexByName = GetEntIndexByName;
    vars.GetEntPtrFromName = GetEntPtrFromName;
    vars.GetEntIndexByPos = GetEntIndexByPos;

#endregion

#region WATCHLIST

    vars.serverState = new MemoryWatcher<int>(ptr_serverState);
    vars.mapName = new StringWatcher(ptr_mapName, ReadStringType.ASCII, 64);
    vars.signOnState = new MemoryWatcher<int>(ptr_signOnState);
    vars.hostState = new MemoryWatcher<int>(ptr_hostState);

    vars.watchList = new MemoryWatcherList()
    {
        vars.mapName,
        vars.serverState,
        vars.signOnState,
        vars.hostState
    };

#endregion

    Action OnSessionStart = () =>
    {
        vars.printTag("new session started", "STATE");
    };
    vars.OnSessionStart = OnSessionStart;
    OnSessionStart();
}

update
{
    vars.watchList.UpdateAll(game);

    if (vars.serverState.Changed)
    {
        vars.printTag("server state changed from " + vars.EvaluateServerState(vars.serverState.Old) + " to " + 
        vars.EvaluateServerState(vars.serverState.Current) , "STATE");
    }

    if (vars.mapName.Changed)
        vars.printTag("map changed from " + vars.mapName.Old + " to " + vars.mapName.Current, "STATE");
    
    if (vars.signOnState.Changed)
    {
        vars.printTag("sign on state changed from " + vars.EvaluateSignOnState(vars.signOnState.Old) + " to " + 
        vars.EvaluateSignOnState(vars.signOnState.Current) , "STATE");

        if (vars.signOnState.Current == 6 && vars.hostState.Current == 4)
            vars.OnSessionStart();
    }

    if (vars.hostState.Changed)
    {
        vars.printTag("host state changed from " + vars.EvaluateHostState(vars.hostState.Old) + " to " + 
        vars.EvaluateHostState(vars.hostState.Current) , "STATE");
    }
}

isLoading
{
    return !(vars.signOnState.Current == 6 && vars.hostState.Current == 4);
}

start
{
    return (settings["AutostartILs"] && vars.hostState.Current == 6 && vars.signOnState.Changed);
}

split
{
    return (vars.hostState.Current == 3 && vars.hostState.Changed && !vars.startmaps.Contains(vars.mapName.Current)); // https://github.com/fatalis/SourceSplit/blob/1056cc59c662e3cb7d77e64aef8bbc26c1e90061/GameMemory.cs#L891-L892
}

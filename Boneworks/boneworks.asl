// Help is welcome! https://discord.gg/mjmpUR8 #speedrunning-disscusion and ping @DerKO

// currentLevel: The id of the current level
// 	Main Menu = 1, BreakRoom = 3, Museum = 4, Streets = 5, Runoff = 6, Sewers = 7, Warehouse = 8, Central Station = 9,
//	Tower = 10, Time Tower = 11, Dungeon = 13, Arena = 14, Throne Room = 15
// MeunButtonCount: The number of buttons displayed in the menu. There are 8 buttons displayed when first opening the "Scene Select" menu.

state("BONEWORKS"){ //This should default to CurrentUpdate values
	//int currentLevel : "GameAssembly.dll", 0x01E7E4E0, 0xB8, 0x590;
	//int menuButtonCount : "GameAssembly.dll", 0x01E6A7F8, 0xB8, 0x20, 0x18;
	int arenaCrabletsKilled : "GameAssembly.dll", 0x01C78E30, 0x8C0, 0x350;
}

state("Boneworks_Oculus_Windows64"){
	// TODO: THIS IS A DECOY
	int arenaCrabletsKilled : "GameAssembly.dll", 0x01C78E30, 0x8C0, 0x350;
}

startup{
	vars.scanTarget = new SigScanTarget(-92, "46 03 80 BF 0A D2 CC BD");
	vars.logFileName = "BONEWORKS.log";
	vars.maxFileSize = 4000000;
	
	vars.SplitOnLoadSettingName = "Split the timer on every loading screen";
	vars.SkipSplitOnFirstLoadingScreenName = "Skip 1st loading screen";
	vars.SkipSplitOnTenthLoadingScreenName = "Skip 10th loading screen";
	vars.LoggingSettingName = "Debug Logging (Log files help solve auto-splitting issues)";
	
	settings.Add(vars.SplitOnLoadSettingName, true);
	settings.Add(vars.SkipSplitOnFirstLoadingScreenName, true, "Skip 1st loading screen", vars.SplitOnLoadSettingName );
	settings.Add(vars.SkipSplitOnTenthLoadingScreenName, true, "Skip 10th loading screen", vars.SplitOnLoadSettingName );
	settings.Add(vars.LoggingSettingName, true);
}

init{
	vars.timerSecondOLD = -1;
	vars.timerSecond = 0;
	vars.timerMinuteOLD = -1;
	vars.timerMinute = 0;
	
	// 2838: x64 asm accesses static pointers using a offset off the very next instruction, 
	// so we'll need to do this to get our desired pointer
	Func<IntPtr, int, int, IntPtr> GetPointerFromOpcode = (ptr, trgOperandOffset, totalSize) =>
	{
		if (ptr == IntPtr.Zero) return IntPtr.Zero;
		byte[] bytes = memory.ReadBytes(ptr + trgOperandOffset, 4);
		if (bytes == null)
		{
			return IntPtr.Zero; 
		}
		Array.Reverse(bytes);
		int offset = Convert.ToInt32(BitConverter.ToString(bytes).Replace("-",""),16);
		IntPtr actualPtr = IntPtr.Add((ptr + totalSize), offset);
		return actualPtr;
	};

	Action<IntPtr, string> ReportPointer = (ptr, name) => 
	{
		if (ptr != IntPtr.Zero) 
			print(name + " found at 0x" + ptr.ToString("X"));
		else print(name + " not found!");
	};


	ProcessModuleWow64Safe gaModule = modules.SingleOrDefault(m => m.FileName.Contains("GameAssembly.dll"));
	if (gaModule == null) {
		Thread.Sleep(10);
		throw new Exception("[WARNING] [SIGSCANNING] GameAssembly module not found or not yet loaded!");
	}
	var gaScanner = new SignatureScanner(game, gaModule.BaseAddress, gaModule.ModuleMemorySize);

	ProcessModuleWow64Safe upModule = modules.SingleOrDefault(m => m.FileName.Contains("UnityPlayer.dll"));
	if (upModule == null) {
		Thread.Sleep(10);
		throw new Exception("[WARNING] [SIGSCANNING] UnityPlayer module not found or not yet loaded!");
	}
	var upScanner = new SignatureScanner(game, upModule.BaseAddress, upModule.ModuleMemorySize);

	var currentLevelSig = new SigScanTarget();
	currentLevelSig.AddSignature(0,	
	"48 8B 0D ?? ?? ?? ??",			// MOV	RCX,qword ptr [DAT_181e6b638]
	"8B F8",						// MOV	EDI,EAX
	"F6 81 ?? ?? ?? ?? 02",			// TEST	byte ptr [RCX + 0x127],0x2
	"74 ??",						// JZ	LAB_180266def
	"83 B9 ?? ?? ?? ?? 00",			// CMP	dword ptr [RCX + 0xd8],0x0
	"75 ??",						// JNZ	LAB_180266def
	"E8 ?? ?? ?? ??",				// CALL	FUN_18014cda0
	"8D 4F ??");					// LEA	ECX,[RDI + 0x1]
	currentLevelSig.OnFound = (proc, scanner, ptr) => {
		IntPtr tempPtr = GetPointerFromOpcode(ptr, 3, 7);
		if (tempPtr == IntPtr.Zero)
			return IntPtr.Zero;
		
		return proc.ReadPointer(proc.ReadPointer(tempPtr) + 0xb8);
	};

	var menuButtonCountSig = new SigScanTarget();
	menuButtonCountSig.AddSignature(0,	
	"48 8b 0d ?? ?? ?? ??",			// MOV	RCX,qword ptr [0x181e6a7f8]
	"48 8b 80 ?? ?? ?? ??",			// MOV	RAX,qword ptr [RAX + 0x80]	
	"48 8b 91 b8 00 00 00");		// MOV	RDX,qword ptr [RCX + 0xb8]
	menuButtonCountSig.OnFound = (proc, scanner, ptr) => {
		IntPtr tempPtr = GetPointerFromOpcode(ptr, 3, 7);
		if (tempPtr == IntPtr.Zero)
			return IntPtr.Zero;
		
		return proc.ReadPointer(proc.ReadPointer(proc.ReadPointer(tempPtr) + 0xb8) + 0x20) + 0x18;
	};

	var loadingSig = new SigScanTarget();
	loadingSig.AddSignature(0,	
	"E8 ?? ?? ?? ??",				// CALL	(targetfunction)
	"B9 20 0D 00 00");				// MOV	ECX, 0xd20
	loadingSig.OnFound = (proc, scanner, ptr) => {
		IntPtr tempPtr = GetPointerFromOpcode(ptr, 1, 5);
		if (tempPtr == IntPtr.Zero)
			return IntPtr.Zero;
			
		return GetPointerFromOpcode(tempPtr, 3, 7) + 0xB9C;
	};

	var entCountSig = new SigScanTarget();
	entCountSig.AddSignature(0,	
	"8B 05 ?? ?? ?? ??",				// MOV	EAX,dword ptr [DAT_181555448]
	"48 8D ?? ?? ??",					// LEA	RCX=>local_828,[RSP + 0x30]
	"41 B9 08 00 00 00");				// MOV	R9D,0x8
	entCountSig.OnFound = (proc, scanner, ptr) => {
		return GetPointerFromOpcode(ptr, 2, 6);
	};

	var watch = System.Diagnostics.Stopwatch.StartNew();

	var currentLevelPtr = gaScanner.Scan(currentLevelSig);
	ReportPointer(currentLevelPtr, "[SIGSCANNING] currentlevel pointer");
	var menuButtonCountPtr = gaScanner.Scan(menuButtonCountSig);
	ReportPointer(menuButtonCountPtr, "[SIGSCANNING] menuButtonCount pointer");

	var loadingPtr = IntPtr.Zero;
	ProcessModuleWow64Safe vrModule = modules.SingleOrDefault(m => m.FileName.Contains("vrclient_x64"));
	if (vrModule == null) {
		Thread.Sleep(10);
        print("[WARNING] [SIGSCANNING] vrclient_x64 module not found or not yet loaded! Auto-split disabled, IGT will be less precise!");
	}
	else
	{
		var vrScanner = new SignatureScanner(game, vrModule.BaseAddress, vrModule.ModuleMemorySize);
		loadingPtr = vrScanner.Scan(loadingSig);
	}
	ReportPointer(loadingPtr, "[SIGSCANNING] loading pointer");
	var entCountPtr = upScanner.Scan(entCountSig);
	ReportPointer(entCountPtr, "[SIGSCANNING] entCount pointer");

	watch.Stop();
	print("[SIGSCANNING] Sigscanning finished after " + (watch.ElapsedMilliseconds / 1000).ToString("0.000") + " seconds!");

    vars.loading = new MemoryWatcher<byte>(loadingPtr);
    vars.menuButtonCount = new MemoryWatcher<int>(menuButtonCountPtr);
	vars.currentLevel = new MemoryWatcher<int>(currentLevelPtr);
	vars.entCount = new MemoryWatcher<int>(entCountPtr);

    vars.watchers = new MemoryWatcherList() {
        vars.loading,
		vars.menuButtonCount,
		vars.entCount
    };

	if (vrModule != null)
		vars.watchers.Add(vars.currentLevel);

	vars.loadCount = 0;
	
	// If the logging setting is checked, this function logs game info to a log file.
	// If the file reaches max size, it will delete the oldest entries.
	vars.Log = (Action<string>)( myString => {
		
		if(settings[vars.LoggingSettingName]){
			
			vars.logwriter = File.AppendText(vars.logFileName);
			
			print("[LOG] " + myString);
			vars.logwriter.WriteLine(myString); 
			
			vars.logwriter.Close();
			
			if((new FileInfo(vars.logFileName)).Length > vars.maxFileSize){
				string[] lines = File.ReadAllLines(vars.logFileName);
				File.WriteAllLines(vars.logFileName, lines.Skip(lines.Length/8).ToArray());
			}
		}
		else{
			if(File.Exists(vars.logFileName)){
				File.Delete(vars.logFileName);
			}
		}
	});
	
	// If a second/minute has passed, log important values.
	vars.PeriodicLogging = (Action)( () => {
		vars.timerMinute = timer.CurrentTime.RealTime.Value.Minutes;
	
		if(vars.timerMinute != vars.timerMinuteOLD){
			vars.timerMinuteOLD = vars.timerMinute;
			
			vars.Log("TimeOfDay: " + DateTime.Now.ToString() + "\n" +
			"Version: " + version.ToString() + "\n" +
			"settings[vars.SplitOnLoadSettingName]: " + settings[vars.SplitOnLoadSettingName].ToString() + "\n" +
			"settings[vars.SkipSplitOnFirstLoadingScreenName]: " + settings[vars.SkipSplitOnFirstLoadingScreenName].ToString() + "\n" +
			"settings[vars.SkipSplitOnTenthLoadingScreenName]: " + settings[vars.SkipSplitOnTenthLoadingScreenName].ToString() + "\n" +
			"settings[vars.LoggingSettingName]: " + settings[vars.LoggingSettingName].ToString() + "\n");
		}
		
		vars.timerSecond = timer.CurrentTime.RealTime.Value.Seconds;
	
		if(vars.timerSecond != vars.timerSecondOLD){
			vars.timerSecondOLD = vars.timerSecond;
			
			vars.Log("RealTime: "+timer.CurrentTime.RealTime.Value.ToString(@"hh\:mm\:ss") + "\n" +
			"GameTime: "+timer.CurrentTime.GameTime.Value.ToString(@"hh\:mm\:ss") + "\n" +
			"loading: " + vars.loading.Current.ToString() + "\n" +
			"loadCount: " + vars.loadCount.ToString() + "\n" +
			"currentLevel: " + vars.currentLevel.Current.ToString() + "\n" +
			"menuButtonCount: " + vars.menuButtonCount.Current.ToString() + "\n" +
			"entCount: " + vars.entCount.Current.ToString() + "\n" +
			"arenaCrabletsKilled: " + current.arenaCrabletsKilled.ToString() + "\n");
		}
	});
}

reset{
	if(vars.menuButtonCount.Current == 8 && vars.menuButtonCount.Old == 0){
		vars.Log("-Resetting-\n");
		return true;
	}
	else if(vars.currentLevel.Current == 1 && vars.currentLevel.Old != 1 && vars.currentLevel.Old != 15){
		vars.Log("-Resetting-\n");
		return true;
	}
}

isLoading{
	return vars.entCount.Current == 0 || vars.loading.Current == 1; //stops timer when loading is 1
}

start{
	if(vars.loading.Current == 1 && vars.loading.Old == 0){
		vars.loadCount = 0;
		vars.Log("-Starting-\n");
		return true;
	}
}

split{
	vars.PeriodicLogging();
	
	if(vars.loading.Current == 1 && vars.loading.Old == 0 && settings[vars.SplitOnLoadSettingName]){
		if(settings[vars.SkipSplitOnFirstLoadingScreenName]){
			if(vars.loadCount == 0){
				vars.loadCount++;
				return false;
			}
		}
		if(settings[vars.SkipSplitOnTenthLoadingScreenName]){
			if(vars.loadCount == 9){
				vars.loadCount++;
				return false;
			}	
		}
		vars.loadCount++;
		vars.Log("-Splitting-\n");
		return true;
	}
	
	if(current.arenaCrabletsKilled == 100 && old.arenaCrabletsKilled != 100){
		return true;
	}
}

update{
	vars.watchers.UpdateAll(game);
}

// Performance Tool:

// var watch = System.Diagnostics.Stopwatch.StartNew();
// Code to measure
// watch.Stop();
// var elapsedMs = watch.ElapsedMilliseconds;
// print(elapsedMs.ToString());

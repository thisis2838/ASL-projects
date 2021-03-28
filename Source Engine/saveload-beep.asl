state("hl2") { }
state("bms") { }
state("portal") { }
state("portal2") { }

init
{
	ProcessModuleWow64Safe engine = modules.FirstOrDefault(x => x.ModuleName.ToLower() == "engine.dll");
	if(engine == null)
	{
		Thread.Sleep(1000);
		print("[SIGSCANNING] All modules aren't yet loaded! Waiting 1 second until next try");
        throw new Exception();
	}

	var serverScanner = new SignatureScanner(game, engine.BaseAddress, engine.ModuleMemorySize);
	
	var loadingByte = new SigScanTarget();
	loadingByte.AddSignature(17,
		"80 3D ?? ?? ?? ?? 00",    // cmp     byte_698EE114, 0
		"74 06",                   // jz      short loc_6936C8FF
		"B8 ?? ?? ?? ??",          // mov     eax, offset aDedicatedServe ; "Dedicated Server"
		"C3",                      // retn
		"83 3D ?? ?? ?? ?? 02",    // cmp     CBaseClientState__m_nSignonState, 2
		"B8 ?? ?? ?? ??");         // mov     eax, offset MultiByteStr
	loadingByte.OnFound = (proc, scanner, ptr) => proc.ReadPointer(ptr, out ptr) ? ptr : IntPtr.Zero;

		// CBaseClientState::m_nSignOnState
	var loadingByte2 = new SigScanTarget();
	loadingByte2.OnFound = (proc, scanner, ptr) => {
		if (!proc.ReadPointer(ptr, out ptr)) // deref instruction
			return IntPtr.Zero;
		if (!proc.ReadPointer(ptr, out ptr)) // deref ptr
			return IntPtr.Zero;
		return IntPtr.Add(ptr, 0x70); // this+0x70 = m_nSignOnState
	};
	
	loadingByte2.AddSignature(14,
		"74 ??",                   // jz      short loc_693D4E22
		"8B 74 87 04",             // mov     esi, [edi+eax*4+4]
		"83 7E 18 00",             // cmp     dword ptr [esi+18h], 0
		"74 2D",                   // jz      short loc_693D4DFC
		"8B 0D ?? ?? ?? ??",       // mov     ecx, baseclientstate
		"8B 49 18");               // mov     ecx, [ecx+18h]
	
	IntPtr d = serverScanner.Scan(loadingByte);
	if (d == IntPtr.Zero) 
		d = serverScanner.Scan(loadingByte2);

	print("loading byte found at 0x" + d.ToString("X"));
	vars.loading = new MemoryWatcher<int>(d);
	vars.loading.Update(game);
}

startup
{
	settings.Add("Beep", true, "Enable beeping");
	settings.SetToolTip("Beep", "Beeps when it's ready to do a save/load");
}

update
{
	vars.loading.Update(game);
	if (settings["Beep"] && vars.loading.Current >= 4 && vars.loading.Old < 4)
	{
		Console.Beep();
	}
}

start
{   

}

reset
{
	
}

split
{
	
}

isLoading { return true; }

gameTime { }
state("bms") { }

init
{
	ProcessModuleWow64Safe server = modules.FirstOrDefault(x => x.ModuleName.ToLower() == "server.dll");
	if(server == null)
	{
		Thread.Sleep(1000);
		vars.print("[SIGSCANNING] All modules aren't yet loaded! Waiting 1 second until next try");
        throw new Exception();
	}

	var serverScanner = new SignatureScanner(game, server.BaseAddress, server.ModuleMemorySize);
	
	// find the pointer that contains the pointer to CGameMovement
	var CGameMovementSig = new SigScanTarget();
	CGameMovementSig.AddSignature(1, "A1 ?? ?? ?? ?? FF 31 8B 30");
	CGameMovementSig.OnFound = (proc, scanner, ptr) => {
		new DeepPointer(ptr, 0x0, 0x0).DerefOffsets(game, out ptr); 
		return ptr;
	};
	vars.CGameMovementPtr = serverScanner.Scan(CGameMovementSig);
	vars.ReportPointer("CGameMovement", vars.CGameMovementPtr);

	// find the function that writes to the aforementioned pointer, this will write bms' vftable pointer to it
	byte[] b = BitConverter.GetBytes(vars.CGameMovementPtr.ToInt32());
	string bmsGameMovementSigRaw = String.Format("C7 05 {0:X02} {1:X02} {2:X02} {3:X02}", b[0], b[1], b[2], b[3]);
	var bmsGameMovementSig = new SigScanTarget(6, bmsGameMovementSigRaw);
	bmsGameMovementSig.OnFound = (proc, scanner, ptr) =>{
		new DeepPointer(ptr, 0x0).DerefOffsets(game, out ptr); 
		return ptr;
	};
	var bmsGameMovementPtr = serverScanner.Scan(bmsGameMovementSig);
	vars.ReportPointer("bms CGameMovement", bmsGameMovementPtr);

	// find hl2's vftable pointer by searching the pointer for the 2nd function under it
	var hl2GameMovementSig = new SigScanTarget(0, "55 8B EC 8B 45 ?? 57 FF 75 ??");
	hl2GameMovementSig.OnFound = (proc, scanner, ptr) => {
		vars.ReportPointer("2nd function under hl2's CGameMovement", ptr);
		var s_scanner = scanner;
		byte[] f_bytesPtr = BitConverter.GetBytes(ptr.ToInt32());
		var s_timer = new Stopwatch();

		var s_ptr = IntPtr.Zero;
		s_timer.Start();
		uint serverEndAddress = (uint)server.BaseAddress + (uint)server.ModuleMemorySize;
		var s_target = new SigScanTarget(-4, String.Format("{0:X02} {1:X02} {2:X02} {3:X02}", f_bytesPtr[0], f_bytesPtr[1], f_bytesPtr[2], f_bytesPtr[3]));
		// because this function is used by both bms' and hl2's cgamemovement we'll have to filter out bad results
		do
		{
			s_ptr = s_scanner.Scan(s_target);
			if (s_ptr == bmsGameMovementPtr)
				s_scanner = new SignatureScanner(game, s_ptr + 0x8, (int)(serverEndAddress - (uint)(s_ptr + 0x8)));
			else break;
		}
		while (s_timer.ElapsedMilliseconds < 5000); // timeout after 5 seconds
		s_timer.Stop();
		return s_ptr;
	};
	var hl2GameMovementPtr = serverScanner.Scan(hl2GameMovementSig);
	vars.ReportPointer("hl2 CGameMovement", hl2GameMovementPtr);

	vars.bmsCGPtrBytes = BitConverter.GetBytes(bmsGameMovementPtr.ToInt32());
	vars.hl2CGPtrBytes = BitConverter.GetBytes(hl2GameMovementPtr.ToInt32());
	game.VirtualProtect((IntPtr)vars.CGameMovementPtr, (int)32, MemPageProtect.PAGE_EXECUTE_READWRITE);
	vars.functional = true;
}

startup
{
	vars.functional = false;

	// we define these here to allow access from shutdown {}
	vars.CGameMovementPtr = IntPtr.Zero;
	vars.hl2CGPtrBytes = new byte[] {0x0, 0x0, 0x0, 0x0};
	vars.bmsCGPtrBytes = new byte[] {0x0, 0x0, 0x0, 0x0};

	Action<string> prints = (msg) => {
		print("[BMS HL2 MOVEMENT RE-ENABLER] " + msg);
	};

	Action<string, IntPtr> ReportPointer = (name, ptr) => {
		if (ptr == IntPtr.Zero)
		{
			prints(name + " wasn't found!! Disabling script!!");
			vars.functional = false;
		}
		else
			prints(name + " found at 0x" + ptr.ToString("X"));
	};

	vars.print = prints;
	vars.ReportPointer = ReportPointer;

	settings.Add("doit", true, "Enable HL2/BMS hybrid movement");
	vars.oldsetting = false;
}

update
{
	if (!vars.functional)
		return false;
	if (settings["doit"] && !vars.oldsetting)
	{
		vars.print("Enabling...");
		memory.WriteBytes((IntPtr)vars.CGameMovementPtr, (byte[])(vars.hl2CGPtrBytes));
	}
	else if (!settings["doit"] && vars.oldsetting)
	{
		vars.print("Disabling...");
		memory.WriteBytes((IntPtr)vars.CGameMovementPtr, (byte[])(vars.bmsCGPtrBytes));
	}
	vars.oldsetting = settings["doit"];
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

shutdown
{
	if (vars.functional)
		memory.WriteBytes((IntPtr)vars.CGameMovementPtr, (byte[])(vars.bmsCGPtrBytes));
}

isLoading { return true; }

gameTime { }
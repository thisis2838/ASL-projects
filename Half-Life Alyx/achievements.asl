state("hlvr") { }

startup
{
	Action<string> prints = (msg) =>
	{
		print("[ALYX ASL] " + msg);
	};
	vars.print = prints;
}

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

	Action<byte[]> PrintBytes = (arr) =>
	{
		vars.print(BitConverter.ToString(arr).Replace("-", " "));
	};

#region SIGNATURE SCANNING

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

	var serverTmpScanner = new SignatureScanner(game, server.BaseAddress, server.ModuleMemorySize);
	var stringTarget = new SigScanTarget("737461745F747261636B65725F64756D705F7374617473");
	var stringRef = new SigScanTarget(7, "4C 8D 05 ?? ?? ?? ?? 48 8D 15 ?? ?? ?? ?? 48 8D 0D ?? ?? ?? ??");
	IntPtr stringPtr = serverScanner.Scan(stringTarget);
	ReportPointer(stringPtr, "string ptr");

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
	IntPtr begin = GetPointerFromOpcode(d + 0x7, 3, 7);
	ReportPointer(begin, "");

	profiler.Stop();
	vars.print("[SIGSCANNING] Signature scanning done in " + profiler.ElapsedMilliseconds * 0.001f + " seconds");


	IntPtr rcxLoc = begin;
	vars.rcxLoc = rcxLoc;
	IntPtr in1 = begin + 0x8;
	IntPtr in2 = in1 + 0x7;
	IntPtr in3 = in2 + 0x3;
	IntPtr in4 = in3 + 0x2;
	
	IntPtr orig1 = server.BaseAddress + 0x703B8;
	IntPtr orig2 = server.BaseAddress + 0x703BD;

	int off1 = (int)((long)rcxLoc - (long)in2);
	byte[] off1bytes = BitConverter.GetBytes(off1);
	int off2 = (int)((long)orig2 - (long)(in4 + 0x5));
	byte[] off2bytes = BitConverter.GetBytes(off2);
	int off3 = (int)((long)in1 - (long)(orig1 + 0x5));
	byte[] off3bytes = BitConverter.GetBytes(off3);

	// mov [rcxLoc],rcx
	byte[] first = new byte[] { 0x48, 0x89, 0x0D, off1bytes[0], off1bytes[1], off1bytes[2], off1bytes[3] };
	// call qword ptr [rax+28]
	byte[] second = new byte[] { 0xFF, 0x50, 0x28 };
	// test al, al
	byte[] third = new byte[] { 0x84, 0xc0 };
	// jump orig2
	byte[] fourth = new byte[] { 0xe9, off2bytes[0], off2bytes[1], off2bytes[2], off2bytes[3] };
	// jump in1
	byte[] jmp = new byte[] { 0xe9, off3bytes[0], off3bytes[1], off3bytes[2], off3bytes[3] };
	
	game.VirtualProtect((IntPtr)begin, (int)128, MemPageProtect.PAGE_EXECUTE_READWRITE);
	game.VirtualProtect((IntPtr)orig1, (int)10, MemPageProtect.PAGE_EXECUTE_READWRITE);
	memory.WriteBytes(in1, first);
	memory.WriteBytes(in2, second);
	memory.WriteBytes(in3, third);
	memory.WriteBytes(in4, fourth);
	memory.WriteBytes(orig1, jmp);

	vars.curRCX = new MemoryWatcher<IntPtr>(rcxLoc);
#endregion

}

update
{
	vars.curRCX.Update(game);
}

split
{
	if ((ulong)vars.curRCX.Current != 0xFFFFFFFFFFFFFFFF)
	{
		vars.print(vars.curRCX.Current.ToString("X"));
		memory.WriteBytes((IntPtr)vars.rcxLoc, BitConverter.GetBytes(0xFFFFFFFFFFFFFFFF));
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

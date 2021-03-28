state("bms") { }
state("hl2") { }
state("portal") { }

init
{
	ProcessModuleWow64Safe server = modules.FirstOrDefault(x => x.ModuleName.ToLower() == "server.dll");
	if(server == null)
	{
		Thread.Sleep(1000);
		vars.print("All modules aren't yet loaded! Waiting 1 second until next try");
        throw new Exception();
	}

	// how this works:
	// the check for when the player is in the void and the cap lives in tryplayermove(), which is
	// seemingly always 2 entires away from checkjumpbutton(), which we have plenty of signature for

	// so find checkjumpbutton(), then get the pointer to it in the vftable, move 2 entries down
	// then inside that function, sigscan the instructions we need and nop them out if the user wants to

	var serverScanner = new SignatureScanner(game, server.BaseAddress, server.ModuleMemorySize);

	// method 1 for searching for CheckJumpButton():
	// find the base pointer for the "xc_uncrouch_on_jump" command, then add 0x1c (getint() offset)
	// and find a reference to that (which should only exist in CheckJumpButton())
	var uncrouchCmdStringTarg = new SigScanTarget(0, "78635F756E63726F7563685F6F6E5F6A756D70");
	uncrouchCmdStringTarg.OnFound = (proc, scanner, ptr) => {
		byte[] b = BitConverter.GetBytes(ptr.ToInt32());
		string e = "68" + BitConverter.ToString(b).Replace("-"," ");
		var target = new SigScanTarget(6, e);
		IntPtr ptrPtr = scanner.Scan(target);
		if (ptrPtr == IntPtr.Zero)
			return IntPtr.Zero;
		IntPtr ret;
		proc.ReadPointer(ptrPtr, out ret);
		// assume getint() is 1c away from base
		ret = IntPtr.Add(ret, 0x1c);
		target = vars.ConvertPtrToSig(ret, 0);
		ret = scanner.Scan(target);
		if (ret == IntPtr.Zero)
			return IntPtr.Zero;
		return ret - 0x1;
	};

	IntPtr uncrouchCmdStringRef = serverScanner.Scan(uncrouchCmdStringTarg);
	vars.ReportPointer(uncrouchCmdStringRef, "uncrouchCmdString ref");

	IntPtr checkJumpButtonPtr = IntPtr.Zero;
	checkJumpButtonPtr = serverScanner.Scan(vars.checkJumpButton);

	// if the patterns fail for us, if we found the uncrouch reference, sigscan backwards
	// until we hit the beginning of the function
	if (uncrouchCmdStringRef != IntPtr.Zero && checkJumpButtonPtr == IntPtr.Zero)
	{
		var targStart = new SigScanTarget();
		targStart.AddSignature(1, "CC 55");
		targStart.AddSignature(1, "CC 83");
		targStart.AddSignature(1, "CC 81");
		targStart.AddSignature(3, "C2 0400 55");
		targStart.AddSignature(3, "C2 0400 83");
		targStart.AddSignature(3, "C2 0400 81");
		for (int i = 0x100; i < 0x500; i += 0x8)
		{
			var newScanner = new SignatureScanner(game, uncrouchCmdStringRef - i, i);
			checkJumpButtonPtr = newScanner.Scan(targStart);

			if (checkJumpButtonPtr != IntPtr.Zero) break;
		} 
	}
		
	if (checkJumpButtonPtr == IntPtr.Zero)
		vars.QuitEarly("CheckJumpButton not found");

	vars.ReportPointer(checkJumpButtonPtr, "CheckJumpButton");

#region FIND INSTRUCTIONS
	vars.funcPointer = vars.ConvertPtrToSig(checkJumpButtonPtr, 0xC);
	IntPtr tryPlayerMovePtr = memory.ReadPointer((IntPtr)serverScanner.Scan(vars.funcPointer));
	if (tryPlayerMovePtr == IntPtr.Zero)
		vars.QuitEarly("TryPlayerMove not found");
	vars.ReportPointer(tryPlayerMovePtr, "TryPlayerMove");

	serverScanner = new SignatureScanner(game, tryPlayerMovePtr, 0x2000);
	vars.instruct1 = serverScanner.Scan(new SigScanTarget(3, "F6 C4 44 0F 8A ?? ?? ?? ??"));
	if (vars.instruct1 == IntPtr.Zero)
		vars.QuitEarly("Instruction 1 not found");
	vars.ReportPointer(vars.instruct1, "predicted target JP instruction");

	serverScanner = new SignatureScanner(game, vars.instruct1 - 0x50, 0x50);
	vars.instruct2 = serverScanner.Scan(new SigScanTarget(0, "0F 85"));
	if (vars.instruct2 == IntPtr.Zero)
		vars.QuitEarly("Instruction 2 not found");
	vars.ReportPointer(vars.instruct2, "predicted target JNE instruction");

	vars.orig1 = memory.ReadBytes((IntPtr)vars.instruct1, 6);
	vars.orig2 = memory.ReadBytes((IntPtr)vars.instruct2, 6);

	game.VirtualProtect((IntPtr)vars.instruct1, (int)6, MemPageProtect.PAGE_EXECUTE_READWRITE);
	game.VirtualProtect((IntPtr)vars.instruct2, (int)6, MemPageProtect.PAGE_EXECUTE_READWRITE);

#endregion
}

startup
{
	
	settings.Add("doit", false, "Patch in new instructions for free oob movement");
	vars.nop = new byte[] {0x90, 0x90, 0x90, 0x90, 0x90, 0x90};
	vars.orig1 = new byte[] {0x90, 0x90, 0x90, 0x90, 0x90, 0x90};
	vars.orig2 = new byte[] {0x90, 0x90, 0x90, 0x90, 0x90, 0x90};

	
	Action<string> QuitEarly = (error) => {
		throw new Exception("[MOVABLE VOID ASL] Something went wrong! " + error);
	};
	
	
	Action<string> prints = (msg) => {
		print("[MOVABLE VOID ASL] " + msg);
	};

	Func<IntPtr, int, SigScanTarget> ConvertPtrToSig = (ptr, offset) => {
		byte[] bytes = BitConverter.GetBytes((uint)ptr);
		return new SigScanTarget(offset, BitConverter.ToString(bytes).Replace("-"," "));
	};

	Action<IntPtr, string> ReportPointer = (ptr, name) => {
		prints(name + ((ptr == IntPtr.Zero) ? " ptr not found!" : (" ptr found at 0x" + ptr.ToString("X"))));
	};

	vars.ConvertPtrToSig = ConvertPtrToSig;
	vars.print = prints;
	vars.ReportPointer = ReportPointer;
	vars.QuitEarly = QuitEarly;

	vars.checkJumpButton = new SigScanTarget();
	vars.checkJumpButton.AddSignature(0, "83 EC 1C 56 8B F1 8B 4E 04 80 B9 04 0A 00 00 00 74 0E 8B 76 08 83 4E 28 02 32 C0 5E 83 C4 1C C3 D9 EE D8 91 70 0D 00 00");
	vars.checkJumpButton.AddSignature(0, "83 EC 1C 56 8B F1 8B 4E 08 80 B9 C4 09 00 00 00 74 0E 8B 76 04 83 4E 28 02 32 C0 5E 83 C4 1C C3 D9 EE D8 91 30 0D 00 00");
	vars.checkJumpButton.AddSignature(0, "55 8B EC 83 EC 20 56 8B F1 8B 4E 04 80 B9 40 0A 00 00 00 74 0E 8B 76 08 83 4E 28 02 32 C0 5E 8B E5 5D C3 F3 0F 10 89 AC 0D 00 00");
	vars.checkJumpButton.AddSignature(0, "55 8B EC 83 EC 18 56 8B F1 8B 4E 04 80 B9 40 0A 00 00 00 74 0E 8B 46 08 83 48 28 02 32 C0 5E 8B E5 5D C3 F3 0F 10 89 AC 0D 00 00");
	vars.checkJumpButton.AddSignature(0, "55 8B EC 51 56 8B F1 57 8B 7E 04 85 FF 74 10 8B 07 8B CF 8B 80 ?? ?? ?? ?? FF D0 84 C0 75 02 33 FF");
	vars.checkJumpButton.AddSignature(0, "55 8B EC 83 EC 18 56 8B F1 8B 4E 04 80 B9 40 0A 00 00 00 74 0E 8B 76 08 83 4E 28 02 32 C0 5E 8B");
	vars.checkJumpButton.AddSignature(0, "55 8B EC 83 EC 0C 56 8B F1 8B 46 04 80 B8 10 0A 00 00 00 74 0E 8B 76 08 83 4E 28 02 32 C0 5E 8B E5 5D C3 E8 08 F9 FF FF 84 C0 75 F0");
	vars.checkJumpButton.AddSignature(0, "55 8B EC 83 EC ?? 56 8B F1 8B 4E 04 80 B9 44 0A 00 00 00 74 0E 8B ?? 08 83 ?? 28 02 32 C0 5E 8B E5 5D C3 F3 0F 10 89 B0 0D 00 00 0F 57 C0 0F 2E");
	vars.checkJumpButton.AddSignature(0, "55 8B EC 83 EC 0C 56 8B F1 8B 46 04 80 B8 9C 0A 00 00 00 74 0E 8B 46 08 83 48 28 02 32 C0");
	vars.checkJumpButton.AddSignature(0, "55 8B EC 83 EC 0C 56 8B F1 8B 46 04 80 B8 78 0A 00 00 00 74 0E 8B 46 08 83 48 28 02 32 C0 5E 8B E5 5D C3 8B 06 8B 80 44 01 00 00 FF D0 84 C0 75");
	vars.checkJumpButton.AddSignature(0, "55 8B EC 83 EC 0C 56 8B F1 8B 46 04 80 B8 84 0A 00 00 00 74 0E 8B 46 08 83 48 28 02 32 C0 5E 8B");
	vars.checkJumpButton.AddSignature(0, "83 EC 14 56 8B F1 8B 4E 08 80 B9 30 09 00 00 00 0F 85 E1 00 00 00 D9 05 ?? ?? ?? ?? D9 81 70 0C 00 00");
	vars.checkJumpButton.AddSignature(0, "81 EC ?? ?? ?? ?? 56 8B F1 8B 4E 10 80 B9 ?? ?? ?? ?? ?? 74 11 8B 76 0C 83 4E 28 02 32 C0 5E 81 C4");
	vars.checkJumpButton.AddSignature(0, "55 8B EC 83 EC 0C 56 8B F1 8B 4E 04 80 B9 ?? ?? ?? ?? ?? 74 07 32 C0 5E 8B E5 5D C3 53 BB");
	vars.checkJumpButton.AddSignature(0, "55 8B EC 83 EC 44 56 89 4D D0 8B 45 D0 8B 48 08 81 C1 ?? ?? ?? ?? E8 ?? ?? ?? ?? 0F B6 C8 85 C9");
	vars.checkJumpButton.AddSignature(0, "55 8B EC 83 EC 20 56 8B F1 8B 4E 04 80 B9 48 0A 00 00 00 74 0E 8B 76 08 83 4E 28 02 32 C0 5E 8B E5 5D C3 F3 0F 10 89 B4 0D 00 00");
	vars.checkJumpButton.AddSignature(0, "55 8B EC 83 EC 18 56 8B F1 8B 4E 04 80 B9 50 0A 00 00 00 74 0E 8B 46 08 83 48 28 02 32 C0 5E 8B E5 5D C3 F3 0F 10 89 D8 0D 00 00");
	vars.checkJumpButton.AddSignature(0, "55 8B EC 83 EC 1C 56 8B F1 8B 4E 04 80 B9 ?? ?? ?? ?? ?? 74 0E 8B 76 08 83 4E 28 02 32 C0 5E 8B E5");
	vars.checkJumpButton.AddSignature(0, "55 8B EC 83 EC 20 32 C0 80 3D ?? ?? ?? ?? 00 56 8B F1 0F B6 C0 B9 01 00 00 00 0F 45 C1 8B 4E 04 89 45 F8 80 B9 DC 09 00 00 00");
	vars.checkJumpButton.AddSignature(0, "55 8B EC 83 EC 18 56 8B F1 8B 4E 04 80 B9 C0 0B 00 00 00 74 ?? 8B 46 08 83 48 28 02 32 C0 5E 8B E5 5D C3");
	

	vars.instruct1 = IntPtr.Zero;
	vars.instruct2 = IntPtr.Zero;
}

update
{
	if (settings["doit"])
	{
		if (!memory.ReadBytes((IntPtr)vars.instruct1, 6).SequenceEqual((byte[])vars.nop))
			memory.WriteBytes((IntPtr)vars.instruct1, (byte[])vars.nop);

		if (!memory.ReadBytes((IntPtr)vars.instruct2, 6).SequenceEqual((byte[])vars.nop))
			memory.WriteBytes((IntPtr)vars.instruct2, (byte[])vars.nop);
	}
	else
	{
		memory.WriteBytes((IntPtr)vars.instruct1, (byte[])vars.orig1);
		memory.WriteBytes((IntPtr)vars.instruct2, (byte[])vars.orig2);
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

shutdown
{
	memory.WriteBytes((IntPtr)vars.instruct1, (byte[])vars.orig1);
	memory.WriteBytes((IntPtr)vars.instruct2, (byte[])vars.orig2);
}

isLoading { return true; }

gameTime { }
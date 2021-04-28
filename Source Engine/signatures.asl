state("hl2") { }
state("bms") { }
state("hdtf") { }

init
{
	vars.print("Initializing...");

	ProcessModuleWow64Safe server = modules.FirstOrDefault(x => x.ModuleName.ToLower() == "server.dll");
	ProcessModuleWow64Safe client = modules.FirstOrDefault(x => x.ModuleName.ToLower() == "client.dll");
	ProcessModuleWow64Safe engine = modules.FirstOrDefault(x => x.ModuleName.ToLower() == "engine.dll");
	if(server == null || client == null || engine == null)
	{
		Thread.Sleep(1000);
		vars.print("All modules aren't yet loaded! Waiting 1 second until next try");
        throw new Exception();
	}

	const int getIntOffset = 0x1c;

	
	Func<IntPtr, uint, string, string, IntPtr> FindRelativeCallReference = (ptr, bound, prefix, suffix) => {
		
		int offset = 1;
		if (prefix != "")
		{
			int l = 0;
			while (l <= prefix.Length - 1)
			{
				if(prefix[l]==' ')
					offset++;

				l++;
			}
			offset++;
		}

		IntPtr ptr3 = IntPtr.Zero;
		SigScanTarget targ = new SigScanTarget(offset, prefix + " E8 ?? ?? ?? FF " + suffix);
		for (int j = 0; j < 4; j++)
		{
			uint end = (uint)ptr + bound;
			uint start = (uint)ptr - bound;
			bound = end - start;

			SignatureScanner scanner = new SignatureScanner(game, (IntPtr)(start), (int)(bound));
			for (int i = 0; i <= bound; i++)
			{
				targ.OnFound = (proc2, scanner2, ptr2) => {
					if (proc2.ReadValue<int>(ptr2) + (uint)ptr2 + 0x4 == (uint)ptr)
						return ptr2;

					bound = (uint)(end - (uint)ptr2);
					scanner.Address = ptr2;
					scanner.Size = (int)bound;
					return IntPtr.Zero;
				};
				ptr3 = scanner.Scan(targ);
				if (ptr3 != IntPtr.Zero)
					break;
			}

			if (ptr3 == IntPtr.Zero)
			{
				switch (j)
				{
					case 1:
						targ = new SigScanTarget(offset, prefix + " E8 ?? ?? ?? 00 " + suffix);
						break;
					case 2:
						targ = new SigScanTarget(offset, prefix + " E9 ?? ?? ?? FF " + suffix);
						break;
					case 3:
						targ = new SigScanTarget(offset, prefix + " E9 ?? ?? ?? 00 " + suffix);
						break;
				}
			}
			else break;
		}
		return ptr3 != IntPtr.Zero ? ptr3 - 0x1 : IntPtr.Zero;
	};

	Func<IntPtr, SignatureScanner, IntPtr> BackTraceToFuncStart = (ptr, scanner) => {

		// common function headers
		var targStart = new SigScanTarget();
		targStart.AddSignature(1, "CC 55");
		targStart.AddSignature(1, "CC 51");
		targStart.AddSignature(1, "CC 83");
		targStart.AddSignature(1, "CC 81");
		targStart.AddSignature(1, "CC A1");
		targStart.AddSignature(3, "C2 ???? 55");
		targStart.AddSignature(3, "C2 ???? 51");
		targStart.AddSignature(3, "C2 ???? A1");
		targStart.AddSignature(3, "C2 ???? 83");
		targStart.AddSignature(3, "C2 ???? 81");

		// search for at least 5 int 3 instructions
		var targStart2 = new SigScanTarget();
		targStart2.AddSignature(0, "CC CC CC CC CC");

		int j = 0x0;

		for (int i = 0x50; i < 0x3000; i += 0x16)
		{
			var newScanner = new SignatureScanner(game, ptr - i, i);
			var firstPtr = newScanner.Scan(targStart);

			if (firstPtr != IntPtr.Zero)
			{
				// if we hit what seems like a function header, find if that pointer is referenced anywhere
				// this will only account for vftable entries or mov instructions
				// call opcodes uses an offset from its subsequent instruction which isn't feasable to scan
				var secondPtr = scanner.Scan(vars.ConvertPtrToSig(firstPtr, 0x0, "", ""));

				if (secondPtr == IntPtr.Zero)
					secondPtr = FindRelativeCallReference(firstPtr, 0x10000, "", "");

				if (secondPtr != IntPtr.Zero)
					return firstPtr;
				else
				{
					// try checking if at least 5 int 3 instructions preceed the function header if we
					// can't find an absolute reference to the function
					j = 0x10;
					var newerScanner = new SignatureScanner(game, firstPtr - j, j + 1);
					var thirdPtr = newerScanner.Scan(targStart2);
					if (thirdPtr != IntPtr.Zero)
						return firstPtr;
				}
			}
		}

		byte curbyte = 0x0;
		byte oldbyte = 0x0;
		byte nopbyte = 0x0;

		for (j = 0x0; j < 2; j++)
		{
			switch (j)
			{
				case 0:
					nopbyte = 0x90;
					break;
				case 1:
					nopbyte = 0xCC;
					break;
			}

			for (int i = 0x0; i < 0x3000; i++)
			{
				IntPtr found = IntPtr.Zero;
				oldbyte = curbyte;
				memory.ReadValue<byte>(ptr - i, out curbyte);

				if (curbyte == 0x90 && oldbyte != 0x90)
				{
					found = FindRelativeCallReference(ptr - i + 1, 0x10000, "", "");
					if (found != IntPtr.Zero)
						return ptr - i + 1;
					else if (memory.ReadBytes(ptr - i - 4, 4).SequenceEqual(new byte[] {nopbyte, nopbyte, nopbyte, nopbyte}))
						return ptr - i + 1;
				}
			}
		}

		return IntPtr.Zero;
	};

	SigScanTarget target = new SigScanTarget();
	SignatureScanner tmpScanner = new SignatureScanner(game, client.BaseAddress, 0x1);
	IntPtr tmpPtr = IntPtr.Zero; 
	IntPtr tmpPtr2 = IntPtr.Zero;


#region client

	vars.print("[CLIENT] Searching for client.dll functions / vars...");

	vars.print("-----------------------------------");

	var clientScanner = new SignatureScanner(game, client.BaseAddress, client.ModuleMemorySize);

	target = vars.ConvertPtrToSig(vars.FindStringAddress("dev/motion_blur", clientScanner), 0x0, "68", "");
	vars.ReportPointer(BackTraceToFuncStart(clientScanner.Scan(target), clientScanner), "DoImageSpaceMotionBlur", "client");
	
	target = vars.ConvertPtrToSig(vars.FindStringAddress("(time_float)", clientScanner), 0x0, "68", "");
	vars.ReportPointer(BackTraceToFuncStart(clientScanner.Scan(target), clientScanner), "HudUpdate", "client");

	target = new SigScanTarget(0, "81 ce 00 00 20 00");
	vars.ReportPointer(BackTraceToFuncStart(clientScanner.Scan(target), clientScanner), "GetButtonBits", "client");

#endregion

	vars.print("-----------------------------------");

#region server

	vars.print("[SERVER] Searching for server.dll functions / vars...");
	
	var serverScanner = new SignatureScanner(game, server.BaseAddress, server.ModuleMemorySize);

	Func<bool> FindCheckJumpButton = () => {

		IntPtr stringRef = IntPtr.Zero;
		tmpPtr2 = vars.FindCVarBase("xc_uncrouch_on_jump", serverScanner);
		if (tmpPtr2 != IntPtr.Zero)
		{
			target = vars.ConvertPtrToSig( + getIntOffset, 0, "","");
			stringRef = serverScanner.Scan(target);

			if (stringRef == IntPtr.Zero)
				stringRef = vars.FindMOVReference(vars.FindCVarBase("xc_uncrouch_on_jump", serverScanner), serverScanner);
		}

		tmpPtr2 = BackTraceToFuncStart(stringRef, serverScanner);
		vars.ReportPointer(tmpPtr2, "CheckJumpButton HL2", "server");


		if (tmpPtr2 != IntPtr.Zero)
		{
			target = vars.ConvertPtrToSig(tmpPtr2, 0, "", "");
			tmpPtr = memory.ReadPointer(serverScanner.Scan(target) + 0xC);
			vars.ReportPointer(tmpPtr, "TryPlayerMove", "server");
			target = vars.ConvertPtrToSig(tmpPtr, 0, "", "");
			tmpScanner = serverScanner;

			do 
			{
				target.OnFound = (d_proc, d_scanner, d_ptr) => {
					IntPtr f_ptr = d_proc.ReadPointer(d_ptr - 0xC);
					if (f_ptr != tmpPtr2)
						vars.ReportPointer(f_ptr, "CheckJumpButton game-specific", "server");
					tmpScanner = new SignatureScanner(game, d_ptr + 0x8, (int)((uint)server.BaseAddress + (uint)server.ModuleMemorySize - (uint)d_ptr - 0x8));
					return f_ptr;
				};
				tmpPtr = tmpScanner.Scan(target);
			}
			while (tmpPtr != IntPtr.Zero);

			
		}

		return true;
		
	};

	IntPtr stringRef = IntPtr.Zero;

	FindCheckJumpButton();

	target = vars.ConvertPtrToSig(vars.FindStringAddress("PM  Got a NaN velocity", serverScanner), 0, "68","");
	vars.print(serverScanner.Scan(target).ToString("X"));
	tmpPtr = BackTraceToFuncStart(serverScanner.Scan(target), serverScanner);
	vars.ReportPointer(tmpPtr, "CheckVelocity", "server");
	//vars.ReportPointer(FindRelativeCallReference(tmpPtr, 0x2000, "D8 ?? ?? D9 ?? ??", ""), "FinishGravity", "server");


#endregion
}

startup
{
	Action<string> prints = (msg) => {
		print("[SE FIND SIGS] " + msg);
	};

	Func<IntPtr, string> ConvertPtrToSigRaw = (ptr) => {
		byte[] bytes = BitConverter.GetBytes((uint)ptr);
		return BitConverter.ToString(bytes).Replace("-"," ");
	};

	Func<IntPtr, int, string, string, SigScanTarget> ConvertPtrToSig = (ptr, offset, prefix, suffix) => {
		byte[] bytes = BitConverter.GetBytes((uint)ptr);
		return new SigScanTarget(offset, prefix + " " + BitConverter.ToString(bytes).Replace("-"," ") + " " + suffix);
	};

	Func<string, SignatureScanner, IntPtr> FindStringAddress = (str, scanner) => {
		var target = new SigScanTarget(0, BitConverter.ToString(Encoding.Default.GetBytes(str)).Replace("-", ""));
		return scanner.Scan(target);
	};

	Func<string, SignatureScanner, IntPtr> FindCVarBase = (str, scanner) => {
		IntPtr stringPtr = FindStringAddress(str, scanner);
		SigScanTarget target = ConvertPtrToSig(stringPtr, 6, "68", "B9 ?? ?? ?? ??");
		target.OnFound = (proc, scanner2, ptr) => proc.ReadPointer(ptr);
		return scanner.Scan(target);
	};

	Func<IntPtr, SignatureScanner, IntPtr> FindMOVReference = (ptr, scanner) => {
		if (ptr == IntPtr.Zero) return ptr;
		
		byte[] bytes = BitConverter.GetBytes((uint)ptr);
		string sig1 = BitConverter.ToString(bytes).Replace("-"," ");

		SigScanTarget target = new SigScanTarget();
		target.AddSignature(1, "8B ?? " + sig1);
		target.AddSignature(1, "8A ?? " + sig1);
		target.AddSignature(1, "A1 " + sig1);
		target.AddSignature(1, "A2 " + sig1);
		target.AddSignature(1, "A3 " + sig1);
		target.AddSignature(1, "B8 ?? " + sig1);
		target.AddSignature(1, "B9 ?? " + sig1);

		return scanner.Scan(target);

	};

	Action<IntPtr, string, string> ReportPointer = (ptr, name, module) => {
		prints("[" + module.ToUpper() + "] " + name + ((ptr == IntPtr.Zero) ? " ptr not found!" : (" ptr found at 0x" + ptr.ToString("X"))));
	};


	vars.ConvertPtrToSig = ConvertPtrToSig;
	vars.print = prints;
	vars.ReportPointer = ReportPointer;
	vars.FindStringAddress = FindStringAddress;
	vars.FindCVarBase = FindCVarBase;
	vars.FindMOVReference = FindMOVReference;
}

update
{

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
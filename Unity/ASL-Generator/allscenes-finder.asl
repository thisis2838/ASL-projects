state("karlson") { }
state("noid") { }
state("AndAllWouldCryBeware") { }

init
{
    // init scanner
    ProcessModuleWow64Safe unityPlayer = game.ModulesWow64Safe().FirstOrDefault(x => x.ModuleName.ToLower() == "unityplayer.dll");
    if (unityPlayer == null)
        unityPlayer = game.ModulesWow64Safe().First();
    var upScanner = new SignatureScanner(game, unityPlayer.BaseAddress, unityPlayer.ModuleMemorySize);

    // find the address of our target string
    var tmpTarget = new SigScanTarget(0, BitConverter.ToString(Encoding.Default.GetBytes("RuntimeInitializeOnLoadManager")).Replace("-", ""));
    IntPtr tmpPtr = upScanner.Scan(tmpTarget);

    // find the reference to string
    if (!game.Is64Bit())
    {
        byte[] tmpBytes = BitConverter.GetBytes((uint)tmpPtr);
        tmpTarget = new SigScanTarget("68 "+ BitConverter.ToString(tmpBytes).Replace("-", " "));
    }  
    else
        tmpTarget = new SigScanTarget("48 8d 15 ?? ?? ?? ?? 48 8b 0d ?? ?? ?? ??");    
    tmpPtr = upScanner.Scan(tmpTarget); 

    // retrace instructions from the reference back to the partial beginning of the function
    while (!memory.ReadBytes(tmpPtr, 0x3).SequenceEqual(new byte[] { 0xCC, 0xCC, 0xCC }))
        tmpPtr = tmpPtr - 0x1;
    tmpPtr = tmpPtr + 0x3;
    print(tmpPtr.ToString("X"));

    // find a JMP reference to the partial beginning we found earlier
    IntPtr tmpPtr2 = tmpPtr;
    // assume the reference is within 0x10000 bytes of our instruction
    var tmpTargets = new List<SigScanTarget>();
    if (!game.Is64Bit())
    {
        tmpTargets.Add(new SigScanTarget(5, "B9 ?? ?? ?? ?? E9 ?? ?? FF FF"));
        tmpTargets.Add(new SigScanTarget(5, "B9 ?? ?? ?? ?? E9 ?? ?? 00 00"));
    }
    else
    {
        tmpTargets.Add(new SigScanTarget(7, "48 8D 0D ?? ?? ?? ?? E9 ?? ?? FF FF"));
        tmpTargets.Add(new SigScanTarget(7, "48 8D 0D ?? ?? ?? ?? E9 ?? ?? 00 00"));
    }
    foreach (SigScanTarget target in tmpTargets)
    {
        SignatureScanner tmpScanner = new SignatureScanner(game, tmpPtr2 - 0x10000, 0x20000);
        target.OnFound = (f_proc, f_scanner, f_ptr) => 
        {
            if (f_ptr + memory.ReadValue<int>(f_ptr + 1) + 5 != tmpPtr2)
            {
                f_scanner.Size -= (int)((long)(f_ptr + 0x1) - (long)f_scanner.Address);
                f_scanner.Address = f_ptr + 0x1;
                f_scanner.Scan(target);
                return IntPtr.Zero;
            }
            return f_ptr;
        };
        tmpPtr = tmpScanner.Scan(target);
        if (tmpPtr != IntPtr.Zero)
            break;
    }
    // the pointer should be inside the instruction immediately before what we found
    tmpPtr = (!game.Is64Bit()) ? memory.ReadPointer(tmpPtr - 0x4) : tmpPtr + memory.ReadValue<int>(tmpPtr - 0x4);
    print("allscenes should be " + tmpPtr.ToString("X"));
}
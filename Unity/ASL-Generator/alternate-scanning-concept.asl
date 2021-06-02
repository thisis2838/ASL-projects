state("karlson") { }

init
{
    Func<SigScanTarget, List<IntPtr>> FindAll = (target) =>
    {
        var foundList = new List<IntPtr>();

        foreach (var page in game.MemoryPages(true).Reverse()) 
        {
            IntPtr d = page.BaseAddress;
            var scanner = new SignatureScanner(game, page.BaseAddress, (int)page.RegionSize);
            while (d != IntPtr.Zero) 
            {
                target.OnFound = (f_proc, f_scanner, f_ptr) => 
                {
                    foundList.Add(f_ptr);
                    f_scanner.Address = f_ptr + 0x1;
                    f_scanner.Size = (int)page.BaseAddress + (int)page.RegionSize - (int)f_scanner.Address;
                    return f_ptr;
                };

                d = scanner.Scan(target);
            }
            
        }
        return foundList;
    };

    Func<IntPtr, List<IntPtr>> GetReferencesToPtr = (ptr) => 
    {
        byte[] bytes = BitConverter.GetBytes((uint)ptr);
        var F_target = new SigScanTarget(0, bytes);

        return FindAll(F_target);
    };

    Func<IntPtr, int[], IntPtr> ReverseOffsets = (ptr, offsets) => 
    {
        IntPtr found = ptr;

        int i = offsets.Length - 1;
        int j = 0;

        var foundList = GetReferencesToPtr(found - offsets[i]);
        if (foundList.Count == 0)
            return IntPtr.Zero;
        else
        {
            
        }
        
        return IntPtr.Zero;
    };

    var potentials = new List<IntPtr>();

    byte[] beginning = Encoding.ASCII.GetBytes("Assets/Scenes/");

    var starget = new SigScanTarget(0, beginning);

    potentials = FindAll(starget);

    print(ReverseOffsets((IntPtr)0x03237A90, new int[] {0x0, 0x28, 0xc, 0x0}).ToString("X"));
}
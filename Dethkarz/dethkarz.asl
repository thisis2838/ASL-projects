state("Dethkarz")
{
    int timeNow : 0x125ae8;
    int rate : 0x406bf0;
    int funcPtr : 0x125AEC;
    int camPtr : 0x141090;
}

startup
{
    vars.curTime = 0f;
    vars.allowed = new List<int>( new int[]{0x00521CC0, 0x004FEFE0});
	vars.curPtr = 0x0;
	
	vars.curFuncPtr = 0x0;
	vars.oldFuncPtr = 0x0;
}

start
{
    vars.curTime = 0f;
}


update
{
    int delta = (current.timeNow - old.timeNow);
	
	// i am now going to attempt what the hell all this code means
	
	// funcPtr 	is a pointer to a specific function that does actions in the game. usually this is according to what function
	// 			a button calls
	// camPtr 	is a pointer to the camera entity in the game. this is reset to 0 when the game loads
	// curPtr 	is a middleman var, it essentially represents the current value for funcPtr, if funcPtr changes according to our logic
	
	//#1: 	sometimes, funcPtr is reset to 0 before being set to another value for a single frame, which would mess up the code
	//		follow it. so i had to had to filter them out
	//#2	check if the funcPtr goes from 0x4FE788 (game load function) to 0x521CC0 (race set up function). if this transition
	//		happens, don't update curPtr.
	//#3	after the transition descrtibed #3 (game finished loading and now initializing the race), check for when our camPtr is
	//		initialized (which basically means game is almost finished loading). if initialized, update camPtr
	//#4	check if the measured delta in the game's internal interator hasn't reset (old < new), while see if our camera pointer
	//		has been initialized (i.e. game has fully finished loading) and our middleman curPtr isn't pointing to the game load function
	
	// the reason why we have to track for the game load function even though the camPtr is seemingly enough to monitor game load is because
	// in menus, camPtr is cleared, while funcPtr isn't. meaning with this logic we can time the menus
	
	//#1
	vars.curFuncPtr = current.funcPtr == 0 ? vars.curFuncPtr : current.funcPtr;
	vars.oldFuncPtr = old.funcPtr == 0 ? vars.oldFuncPtr : old.funcPtr;
	
	if (vars.curFuncPtr != vars.oldFuncPtr)
	{
		//#2
		if (vars.oldFuncPtr == 0x004FE788 && vars.curFuncPtr == 0x00521CC0)
			vars.curPtr = 0x004FE788;
		else
			vars.curPtr = current.funcPtr;
	}
	//#3
	else if (current.camPtr != old.camPtr && current.camPtr != 0 && vars.curPtr == 0x004FE788)
		vars.curPtr = current.funcPtr;
		
	//#4
    if (delta > 0 && (current.camPtr != 000000 || vars.curPtr != 0x004FE788))
    {
        vars.curTime += delta / (float)current.rate;
    }
}

isLoading
{
    return true;
}

gameTime
{
    return TimeSpan.FromSeconds(vars.curTime);
}
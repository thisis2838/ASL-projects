// Death Giver 2 ASL v2.0 (c) Daemon

state("stdrt", "standalone")
{
	byte level : 0x05760C, 0x1EC;
}

state("stdrt", "gamescollection")
{
	byte level : 0x0AB4B4, 0x1EC;
}

startup {
	settings.Add("skip1", true, "Disable resetting for exit from level 17");
}

init
{
	print("Found Death Giver 2!");
	
	if (modules.First().ModuleMemorySize == 393216) {
		version = "standalone";
	} else if (modules.First().ModuleMemorySize == 1064960) {
		version = "gamescollection";
	}
}

reset
{ 
	if (current.level == 1 && old.level != 1) {
		if (settings["skip1"] && old.level == 17) {
			return false;
		}
		return true;
	}
}

start
{
	if (current.level == 6 && old.level == 5) {
		print("Death Giver 2 ASL: Timer started");
		return true;
	}
}

split
{
	if (current.level == old.level+1 && old.level != 1) {
		return true;
	}
}
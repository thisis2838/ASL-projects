state("In Sound Mind")
{
	bool active : "unityplayer.dll", 0x19fb7c8, 0x78;
}

isLoading
{
	return !current.active;
}

state("bms") { }

startup {

}

init
{
	vars.xVel = new MemoryWatcher<float>(new DeepPointer("client.dll", 0x56282c, 0xf8));
	vars.yVel = new MemoryWatcher<float>(new DeepPointer("client.dll", 0x56282c, 0xfc));
	vars.zVel = new MemoryWatcher<float>(new DeepPointer("client.dll", 0x56282c, 0x100));
	
	vars.xPos = new MemoryWatcher<float>(new DeepPointer("client.dll", 0x6a31f8));
	vars.yPos = new MemoryWatcher<float>(new DeepPointer("client.dll", 0x6a31f8 + 0x4));
	vars.zPos = new MemoryWatcher<float>(new DeepPointer("client.dll", 0x6a31f8 + 0x8));
	
	vars.watcher = new MemoryWatcherList() {
	vars.xPos,
	vars.yPos,
	vars.zPos,
	vars.xVel,
	vars.yVel,
	vars.zVel};
	
	var screen = Screen.AllScreens.Any(x => x.Primary == false) ? Screen.AllScreens.Where(x => x.Primary == false).First() : Screen.PrimaryScreen;
    vars.popUpForm = new Form {
        Icon = System.Drawing.Icon.ExtractAssociatedIcon("LiveSplit.exe"),
        StartPosition = FormStartPosition.Manual,
        Location = new System.Drawing.Point(screen.Bounds.X + 50, 80),
        MinimumSize = new System.Drawing.Size(400, 0),
        Padding = new Padding(5),
        Font = new System.Drawing.Font("Courier New", 10),
        MaximizeBox = false,
        TopMost = true,
        AutoSize = true,
        AutoSizeMode = AutoSizeMode.GrowAndShrink
    };

    vars.isFormOpen = false;
    vars.formClose = (System.Windows.Forms.FormClosingEventHandler) ((s, e) => { vars.isFormOpen = false; });
    vars.popUpForm.FormClosing += vars.formClose;

    vars.openForm = (Action<string, string>) ((gameName, type) => {
        vars.popUpForm.Text = gameName + " | " + type;
        vars.isFormOpen = true;
        vars.popUpForm.Show();
    });

    vars.formLabel = (Action<string, string>) ((labelName, contents) => {
        Form.ControlCollection formControls = vars.popUpForm.Controls;
        if (formControls.ContainsKey(labelName)) {
            formControls[labelName].Text = contents;
        } else {
            formControls.Add(new Label {
                Name = labelName,
                Location = new System.Drawing.Point(5, 5 + 15 * formControls.Count),
                AutoSize = true,
                Text = contents
            });
        }
    });
	
	vars.formLabel("label1", "");
	vars.formLabel("label2", "");
	vars.formLabel("label1z", "");
	vars.formLabel("label2a", "");
    vars.openForm("BMS", "info");
}

startup
{
}

update
{
	const string format = "0.0000";
	vars.watcher.UpdateAll(game);
	vars.formLabel("label1","pos       " 	+ vars.xPos.Current.ToString(format) + " " 
											+ vars.yPos.Current.ToString(format) + " " 
											+ vars.zPos.Current.ToString(format));
											
	vars.formLabel("label1a","pos delta " 	+ (vars.xPos.Current - vars.xPos.Old).ToString(format) + " " 
											+ (vars.yPos.Current - vars.yPos.Old).ToString(format) + " " 
											+ (vars.zPos.Current - vars.zPos.Old).ToString(format));
											
	vars.formLabel("label2","vel       " 	+ vars.xVel.Current.ToString(format) + " " 
											+ vars.yVel.Current.ToString(format) + " " 
											+ vars.zVel.Current.ToString(format));
											
	vars.formLabel("label2a","vel delta " 	+ (vars.xVel.Current - vars.xVel.Old).ToString(format) + " " 
											+ (vars.yVel.Current - vars.yVel.Old).ToString(format) + " " 
											+ (vars.zVel.Current - vars.zVel.Old).ToString(format));
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
	vars.popUpForm.Close();
}

isLoading { return true; }

gameTime { }
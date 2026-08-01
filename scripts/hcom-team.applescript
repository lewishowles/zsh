on run arguments
	set reviewerCommand to item 1 of arguments
	set implementerCommand to item 2 of arguments
	set scoutCommand to item 3 of arguments

	tell application "Ghostty"
		activate

		if (count of windows) = 0 then
			error "Open a Ghostty terminal first."
		end if

		set currentWindow to front window
		set currentTab to selected tab of currentWindow
		set orchestratorTerminal to focused terminal of currentTab

		set implementerTerminal to split orchestratorTerminal direction right
		set reviewerTerminal to split orchestratorTerminal direction down
		set scoutTerminal to split implementerTerminal direction down

		perform action "resize_split:down,150" on orchestratorTerminal
		perform action "resize_split:down,150" on implementerTerminal

		my runCommand(reviewerTerminal, reviewerCommand)
		my runCommand(implementerTerminal, implementerCommand)
		my runCommand(scoutTerminal, scoutCommand)

		focus orchestratorTerminal
	end tell
end run

on runCommand(targetTerminal, commandText)
	tell application "Ghostty"
		input text commandText to targetTerminal
		send key "enter" to targetTerminal
	end tell
end runCommand

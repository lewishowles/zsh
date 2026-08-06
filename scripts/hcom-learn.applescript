on run arguments
	set scoutCommand to item 1 of arguments

	tell application "Ghostty"
		activate

		if (count of windows) = 0 then
			error "Open a Ghostty terminal first."
		end if

		set currentWindow to front window
		set currentTab to selected tab of currentWindow
		set learnerTerminal to focused terminal of currentTab
		set scoutTerminal to split learnerTerminal direction right

		my runCommand(scoutTerminal, scoutCommand)
		focus learnerTerminal
	end tell
end run

on runCommand(targetTerminal, commandText)
	tell application "Ghostty"
		input text commandText to targetTerminal
		send key "enter" to targetTerminal
	end tell
end runCommand

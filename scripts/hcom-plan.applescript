on run arguments
	set planCodexCommand to item 1 of arguments
	set scoutClaudeCommand to item 2 of arguments
	set scoutCodexCommand to item 3 of arguments

	tell application "Ghostty"
		activate

		if (count of windows) = 0 then
			error "Open a Ghostty terminal first."
		end if

		set currentWindow to front window
		set currentTab to selected tab of currentWindow
		set planClaudeTerminal to focused terminal of currentTab

		set planCodexTerminal to split planClaudeTerminal direction right
		set scoutClaudeTerminal to split planClaudeTerminal direction down
		set scoutCodexTerminal to split planCodexTerminal direction down

		perform action "resize_split:down,150" on planClaudeTerminal
		perform action "resize_split:down,150" on planCodexTerminal

		my runCommand(planCodexTerminal, planCodexCommand)
		my runCommand(scoutClaudeTerminal, scoutClaudeCommand)
		my runCommand(scoutCodexTerminal, scoutCodexCommand)

		focus planClaudeTerminal
	end tell
end run

on runCommand(targetTerminal, commandText)
	tell application "Ghostty"
		input text commandText to targetTerminal
		send key "enter" to targetTerminal
	end tell
end runCommand

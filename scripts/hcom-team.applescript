on run arguments
	set reviewerCommand to item 1 of arguments
	set implementerCommand to item 2 of arguments
	set scoutCommand to item 3 of arguments
	set previousTerminalIdText to item 4 of arguments
	set terminalIdSeparator to "|"

	tell application "Ghostty"
		activate

		if (count of windows) = 0 then
			error "Open a Ghostty terminal first."
		end if

		set currentWindow to front window
		set currentTab to selected tab of currentWindow
		set orchestratorTerminal to focused terminal of currentTab
		set orchestratorTerminalId to id of orchestratorTerminal

		if previousTerminalIdText is not "" then
			set originalTextItemDelimiters to AppleScript's text item delimiters
			set AppleScript's text item delimiters to terminalIdSeparator
			set previousTerminalIds to text items of previousTerminalIdText
			set AppleScript's text item delimiters to originalTextItemDelimiters

			if item 1 of previousTerminalIds is not orchestratorTerminalId then
				error "Run the previous team command from its orchestrator panel."
			end if

			set existingTerminals to get terminals of currentTab

			repeat with existingTerminal in existingTerminals
				set existingTerminalId to id of existingTerminal

				if existingTerminalId is not orchestratorTerminalId and previousTerminalIds contains existingTerminalId then
					close existingTerminal
				end if
			end repeat
		end if

		set implementerTerminal to split orchestratorTerminal direction right
		set reviewerTerminal to split orchestratorTerminal direction down
		set scoutTerminal to split implementerTerminal direction down

		perform action "resize_split:down,150" on orchestratorTerminal
		perform action "resize_split:down,150" on implementerTerminal

		my runCommand(reviewerTerminal, reviewerCommand)
		my runCommand(implementerTerminal, implementerCommand)
		my runCommand(scoutTerminal, scoutCommand)

		focus orchestratorTerminal

		set teamTerminalIds to {orchestratorTerminalId, id of reviewerTerminal, id of implementerTerminal, id of scoutTerminal}
		set originalTextItemDelimiters to AppleScript's text item delimiters
		set AppleScript's text item delimiters to terminalIdSeparator
		set teamTerminalIdText to teamTerminalIds as text
		set AppleScript's text item delimiters to originalTextItemDelimiters

		return teamTerminalIdText
	end tell
end run

on runCommand(targetTerminal, commandText)
	tell application "Ghostty"
		input text commandText to targetTerminal
		send key "enter" to targetTerminal
	end tell
end runCommand

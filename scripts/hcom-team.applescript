on run arguments
	if (count of arguments) > 0 and item 1 of arguments is "--close" then
		if (count of arguments) > 1 then
			my closeTrackedTerminals(item 2 of arguments)
		end if

		return
	end if

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

		set frontGhosttyWindow to front window
		set selectedGhosttyTab to selected tab of frontGhosttyWindow
		set orchestratorTerminal to focused terminal of selectedGhosttyTab
		set orchestratorTerminalId to id of orchestratorTerminal

		if previousTerminalIdText is not "" then
			set originalTextItemDelimiters to AppleScript's text item delimiters
			set AppleScript's text item delimiters to terminalIdSeparator
			set previousTerminalIds to text items of previousTerminalIdText
			set AppleScript's text item delimiters to originalTextItemDelimiters

			if item 1 of previousTerminalIds is not orchestratorTerminalId then
				error "Run the previous team command from its orchestrator panel."
			end if

			set existingTerminals to get terminals of selectedGhosttyTab

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

on closeTrackedTerminals(terminalIdText)
	if terminalIdText is "" then
		return
	end if

	set terminalIdSeparator to "|"
	set originalTextItemDelimiters to AppleScript's text item delimiters
	set AppleScript's text item delimiters to terminalIdSeparator
	set trackedTerminalIds to text items of terminalIdText
	set AppleScript's text item delimiters to originalTextItemDelimiters

	try
		tell application "Ghostty"
			repeat with currentWindow in windows
				repeat with activeTab in tabs of currentWindow
					set currentTerminals to get terminals of activeTab

					repeat with currentTerminal in currentTerminals
						set currentTerminalId to id of currentTerminal

						if trackedTerminalIds contains currentTerminalId then
							try
								close currentTerminal
							end try
						end if
					end repeat
				end repeat
			end repeat
		end tell
	end try
end closeTrackedTerminals

on runCommand(targetTerminal, commandText)
	tell application "Ghostty"
		input text commandText to targetTerminal
		send key "enter" to targetTerminal
	end tell
end runCommand

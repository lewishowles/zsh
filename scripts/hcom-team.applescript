-- Creates the Ghostty team layout, starts the three teammate commands, and
-- returns the four pane IDs joined by pipe characters. With --close, delegates
-- to closeTrackedTerminals and returns without creating panes. When prior pane
-- IDs are supplied, verifies the focused terminal is the prior orchestrator and
-- closes the prior team's other tracked panes before creating the new layout.
-- Argument access, Ghostty operations, split/resize actions, and command input
-- errors propagate.
-- @param arguments
--     Launch commands and prior pane IDs, or --close plus tracked pane IDs.
on run arguments
	if (count of arguments) > 0 and item 1 of arguments is "--close" then
		if (count of arguments) > 1 then
			my closeTrackedTerminals(item 2 of arguments)
		end if

		return
	end if

	-- Command text for the reviewer pane.
	set reviewerCommand to item 1 of arguments
	-- Command text for the implementer pane.
	set implementerCommand to item 2 of arguments
	-- Command text for the scout pane.
	set scoutCommand to item 3 of arguments
	-- Pipe-separated IDs from the previous same-shell team, if any.
	set previousTerminalIdText to item 4 of arguments
	-- Delimiter shared by the shell and AppleScript ID serialisation.
	set terminalIdSeparator to "|"

	tell application "Ghostty"
		activate

		if (count of windows) = 0 then
			error "Open a Ghostty terminal first."
		end if

		-- The front Ghostty window used for the new team.
		set frontGhosttyWindow to front window
		-- The selected tab containing the launching shell.
		set selectedGhosttyTab to selected tab of frontGhosttyWindow
		-- The focused terminal that becomes the orchestrator pane.
		set orchestratorTerminal to focused terminal of selectedGhosttyTab
		-- Stable ID used to verify relaunch scope and return the pane list.
		set orchestratorTerminalId to id of orchestratorTerminal

		if previousTerminalIdText is not "" then
			-- Preserve the caller's delimiter setting while splitting prior IDs.
			set originalTextItemDelimiters to AppleScript's text item delimiters
			set AppleScript's text item delimiters to terminalIdSeparator
			-- Prior pane IDs used to verify the focused orchestrator and close teammates.
			set previousTerminalIds to text items of previousTerminalIdText
			set AppleScript's text item delimiters to originalTextItemDelimiters

			if item 1 of previousTerminalIds is not orchestratorTerminalId then
				error "Run the previous team command from its orchestrator panel."
			end if

			-- Existing terminals in the selected tab that may belong to the prior team.
			set existingTerminals to get terminals of selectedGhosttyTab

			repeat with existingTerminal in existingTerminals
				-- Current prior-team candidate being checked against the stored IDs.
				set existingTerminalId to id of existingTerminal

				if existingTerminalId is not orchestratorTerminalId and previousTerminalIds contains existingTerminalId then
					close existingTerminal
				end if
			end repeat
		end if

		-- New implementer pane created from the focused orchestrator pane.
		set implementerTerminal to split orchestratorTerminal direction right
		-- New reviewer pane created from the focused orchestrator pane.
		set reviewerTerminal to split orchestratorTerminal direction down
		-- New scout pane created from the implementer pane.
		set scoutTerminal to split implementerTerminal direction down

		perform action "resize_split:down,150" on orchestratorTerminal
		perform action "resize_split:down,150" on implementerTerminal

		my runCommand(reviewerTerminal, reviewerCommand)
		my runCommand(implementerTerminal, implementerCommand)
		my runCommand(scoutTerminal, scoutCommand)

		focus orchestratorTerminal

		-- IDs in orchestrator, reviewer, implementer, scout order.
		set teamTerminalIds to {orchestratorTerminalId, id of reviewerTerminal, id of implementerTerminal, id of scoutTerminal}
		-- Saved delimiter setting restored after serialising new IDs.
		set originalTextItemDelimiters to AppleScript's text item delimiters
		set AppleScript's text item delimiters to terminalIdSeparator
		-- New pane IDs joined with the shared separator for the shell.
		set teamTerminalIdText to teamTerminalIds as text
		set AppleScript's text item delimiters to originalTextItemDelimiters

		return teamTerminalIdText
	end tell
end run

-- Closes the tracked Ghostty panes across all windows and tabs. Empty input
-- succeeds without work. Individual close errors and outer Ghostty traversal
-- errors are suppressed so missing panes and repeated stops remain harmless.
-- @param terminalIdText
--     Pipe-separated Ghostty terminal IDs to close.
on closeTrackedTerminals(terminalIdText)
	if terminalIdText is "" then
		return
	end if

	-- Delimiter used to split the shell's pipe-separated pane IDs.
	set terminalIdSeparator to "|"
	-- Delimiter setting restored after splitting the close input.
	set originalTextItemDelimiters to AppleScript's text item delimiters
	set AppleScript's text item delimiters to terminalIdSeparator
	-- IDs whose matching Ghostty panes should be closed.
	set trackedTerminalIds to text items of terminalIdText
	set AppleScript's text item delimiters to originalTextItemDelimiters

	try
		tell application "Ghostty"
			-- Window currently being scanned for tracked panes.
			repeat with currentWindow in windows
				-- Tab currently being scanned for tracked panes.
				repeat with activeTab in tabs of currentWindow
					-- Terminals in the tab currently being scanned.
					set currentTerminals to get terminals of activeTab

					repeat with currentTerminal in currentTerminals
						-- Terminal candidate whose ID is compared with the tracked list.
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

-- Sends one launch command and Enter to a Ghostty terminal. Input or key-send
-- errors propagate to the caller so pane setup cannot be reported as complete.
-- @param targetTerminal
--     Ghostty terminal that receives the command.
-- @param commandText
--     Command text sent before the Enter key.
on runCommand(targetTerminal, commandText)
	tell application "Ghostty"
		input text commandText to targetTerminal
		send key "enter" to targetTerminal
	end tell
end runCommand

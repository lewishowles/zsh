-- Creates the Ghostty team layout, starts the three teammate commands, and
-- returns the four pane IDs joined by pipe characters. With --close, delegates
-- to closeTrackedTerminals, optionally focuses a remaining pane, and returns
-- without creating panes. When prior pane IDs are supplied, verifies the origin
-- terminal is the prior orchestrator and closes the prior team's other tracked
-- panes before creating the new layout. The shell supplies the origin pane ID
-- before quota allocation so the layout can use it after a tab change. If that
-- pane has closed, the launch stops instead of using the front tab.
-- Focus never moves to Ghostty; the human's pane is restored only if Ghostty was in front.
-- Argument access, Ghostty operations, split/resize actions, and command input
-- errors propagate.
-- @param arguments
--     Launch commands, prior pane IDs, and the origin pane ID, or --close plus tracked pane IDs.
on run arguments
	if (count of arguments) > 0 and item 1 of arguments is "--close" then
		if (count of arguments) > 1 then
			-- Optional pane restored after tracked teammates close.
			set focusTerminalId to ""
			if (count of arguments) > 2 then
				set focusTerminalId to item 3 of arguments
			end if

			my closeTrackedTerminals(item 2 of arguments, focusTerminalId)
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
	-- Shells that loaded the launcher before the origin pane ID existed pass only four arguments.
	if (count of arguments) < 5 then
		error "This shell has an older team launcher loaded. Run exec zsh, then try again."
	end if

	-- ID of the pane that ran the team command, noted by the shell before the quota wait.
	set originTerminalId to item 5 of arguments
	-- Delimiter shared by the shell and AppleScript ID serialisation.
	set terminalIdSeparator to "|"

	tell application "Ghostty"
		-- The tab that contained the launching shell.
		set originGhosttyTab to missing value
		-- The launching shell, used for the splits and relaunch check.
		set orchestratorTerminal to missing value
		-- Window being searched for the launching pane.
		repeat with currentWindow in windows
			-- Tab being searched for the launching pane.
			repeat with currentTab in tabs of currentWindow
				-- Pane whose ID is compared with the one captured before the quota wait.
				repeat with currentTerminal in terminals of currentTab
					if id of currentTerminal is originTerminalId then
						set originGhosttyTab to contents of currentTab
						set orchestratorTerminal to contents of currentTerminal
						exit repeat
					end if
				end repeat
				if orchestratorTerminal is not missing value then exit repeat
			end repeat
			if orchestratorTerminal is not missing value then exit repeat
		end repeat
		if orchestratorTerminal is missing value then
			error "The Ghostty pane that launched this team has closed. Run the command again from an open pane."
		end if

		-- Whether the human is using Ghostty now. Focus is restored only then, so
		-- a human who moved to another app during the quota wait stays there.
		set ghosttyIsFrontmost to frontmost
		if ghosttyIsFrontmost then
			-- The Ghostty window the human is looking at now.
			set frontGhosttyWindow to front window
			-- The tab the human is looking at now, which may differ from the origin tab.
			set selectedGhosttyTab to selected tab of frontGhosttyWindow
			-- The pane focus returns to after the splits, so the human's view does not move.
			set restoreTerminal to focused terminal of selectedGhosttyTab
		end if

		-- Stable ID used to verify relaunch scope and return the pane list.
		set orchestratorTerminalId to id of orchestratorTerminal

		-- Original layout error saved until focus restoration is attempted.
		set layoutErrorMessage to missing value
		try
			if previousTerminalIdText is not "" then
				-- Preserve the caller's delimiter setting while splitting prior IDs.
				set originalTextItemDelimiters to AppleScript's text item delimiters
				set AppleScript's text item delimiters to terminalIdSeparator
				-- Prior pane IDs used to verify the origin orchestrator and close teammates.
				set previousTerminalIds to text items of previousTerminalIdText
				set AppleScript's text item delimiters to originalTextItemDelimiters

				if item 1 of previousTerminalIds is not orchestratorTerminalId then
					error "Run the previous team command from its orchestrator panel."
				end if

				-- Existing terminals in the origin tab that may belong to the prior team.
				set existingTerminals to get terminals of originGhosttyTab

				repeat with existingTerminal in existingTerminals
					-- Current prior-team candidate being checked against the stored IDs.
					set existingTerminalId to id of existingTerminal

					if existingTerminalId is not orchestratorTerminalId and previousTerminalIds contains existingTerminalId then
						close existingTerminal
					end if
				end repeat
			end if

			-- New implementer pane created from the originating orchestrator pane.
			set implementerTerminal to split orchestratorTerminal direction right
			-- New reviewer pane created from the originating orchestrator pane.
			set reviewerTerminal to split orchestratorTerminal direction down
			-- New scout pane created from the implementer pane.
			set scoutTerminal to split implementerTerminal direction down

			perform action "resize_split:down,150" on orchestratorTerminal
			perform action "resize_split:down,150" on implementerTerminal

			my runCommand(reviewerTerminal, reviewerCommand)
			my runCommand(implementerTerminal, implementerCommand)
			my runCommand(scoutTerminal, scoutCommand)

			-- IDs in orchestrator, reviewer, implementer, scout order.
			set teamTerminalIds to {orchestratorTerminalId, id of reviewerTerminal, id of implementerTerminal, id of scoutTerminal}
			-- Saved delimiter setting restored after serialising new IDs.
			set originalTextItemDelimiters to AppleScript's text item delimiters
			set AppleScript's text item delimiters to terminalIdSeparator
			-- New pane IDs joined with the shared separator for the shell.
			set teamTerminalIdText to teamTerminalIds as text
			set AppleScript's text item delimiters to originalTextItemDelimiters

		on error errorMessage number errorNumber
			set layoutErrorMessage to errorMessage
			-- Original layout error number, re-raised with the message.
			set layoutErrorNumber to errorNumber
		end try

		-- Restore the human's pane after the layout succeeds or fails, only when
		-- Ghostty was in front. The saved pane may have been an old teammate pane
		-- that relaunch cleanup closed; focus then goes to the orchestrator, which
		-- is in the origin tab.
		if ghosttyIsFrontmost then
			try
				focus restoreTerminal
			on error
				try
					focus orchestratorTerminal
				end try
			end try
		end if
		if layoutErrorMessage is not missing value then
			error layoutErrorMessage number layoutErrorNumber
		end if
		return teamTerminalIdText
	end tell
end run

-- Closes the tracked Ghostty panes across all windows and tabs. Empty input
-- succeeds without work. Individual close errors and outer Ghostty traversal
-- errors are suppressed so missing panes and repeated stops remain harmless.
-- @param terminalIdText
--     Pipe-separated Ghostty terminal IDs to close.
-- @param focusTerminalId
--     Optional Ghostty terminal ID to focus after closing tracked panes.
on closeTrackedTerminals(terminalIdText, focusTerminalId)
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
	-- Remaining Ghostty terminal to focus after cleanup, when found.
	set focusTerminal to missing value

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

						if currentTerminalId is focusTerminalId then
							set focusTerminal to contents of currentTerminal
						end if

						if trackedTerminalIds contains currentTerminalId then
							try
								close currentTerminal
							end try
						end if
					end repeat
				end repeat
			end repeat

			if focusTerminal is not missing value then
				focus focusTerminal
			end if
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

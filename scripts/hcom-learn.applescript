-- Opens a right-side Ghostty pane for the Scout beside the pane that ran the learner command.
--
-- @param arguments
--     The shell command to start the Scout and the launching pane ID.
on run arguments
	-- Shell command typed into the newly created Scout terminal.
	set scoutCommand to item 1 of arguments
	-- Shells that loaded the launcher before it captured the launching pane pass only one argument.
	if (count of arguments) < 2 then
		error "This shell has an older learn launcher loaded. Run exec zsh, then try again."
	end if
	-- ID of the pane that ran the learner command.
	set originTerminalId to item 2 of arguments

	tell application "Ghostty"
		-- The launching shell, used for the split.
		set learnerTerminal to missing value
		-- Window being searched for the launching pane.
		repeat with currentWindow in windows
			-- Tab being searched for the launching pane.
			repeat with currentTab in tabs of currentWindow
				-- Pane whose ID is compared with the one noted when the command started.
				repeat with currentTerminal in terminals of currentTab
					if id of currentTerminal is originTerminalId then
						set learnerTerminal to contents of currentTerminal
						exit repeat
					end if
				end repeat
				if learnerTerminal is not missing value then exit repeat
			end repeat
			if learnerTerminal is not missing value then exit repeat
		end repeat
		if learnerTerminal is missing value then
			error "The Ghostty pane that launched this learner has closed. Run the command again from an open pane."
		end if

		-- Whether the human is using Ghostty now. Focus is restored only then.
		set ghosttyIsFrontmost to frontmost
		if ghosttyIsFrontmost then
			-- The Ghostty window the human is looking at now.
			set frontGhosttyWindow to front window
			-- The tab the human is looking at now, which may differ from the launching tab.
			set selectedGhosttyTab to selected tab of frontGhosttyWindow
			-- The pane focus returns to after the split, so the human's view does not move.
			set restoreTerminal to focused terminal of selectedGhosttyTab
		end if

		-- Original layout error saved until focus restoration is attempted.
		set layoutErrorMessage to missing value
		try
			-- New right-side terminal reserved for the Scout.
			set scoutTerminal to split learnerTerminal direction right

			my runCommand(scoutTerminal, scoutCommand)
		on error errorMessage number errorNumber
			set layoutErrorMessage to errorMessage
			-- Original layout error number, re-raised with the message.
			set layoutErrorNumber to errorNumber
		end try

		-- Restore the pane the human was using, if Ghostty was in front. A closed
		-- pane is skipped so any layout error still reaches the shell.
		if ghosttyIsFrontmost then
			try
				focus restoreTerminal
			end try
		end if
		if layoutErrorMessage is not missing value then
			error layoutErrorMessage number layoutErrorNumber
		end if
	end tell
end run

-- Types a command into a Ghostty terminal and submits it.
--
-- @param {terminal} targetTerminal
--     Ghostty terminal that receives the command.
-- @param {string} commandText
--     Shell command to type and submit.
on runCommand(targetTerminal, commandText)
	tell application "Ghostty"
		input text commandText to targetTerminal
		send key "enter" to targetTerminal
	end tell
end runCommand

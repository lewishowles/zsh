-- Creates the five-pane insights-review layout and starts the supplied reviewer, scout and consolidator commands.
--
-- @param {list} arguments
--     The Codex reviewer command, both scout commands, the consolidator command and the launching pane ID.
on run arguments
	-- Shells that loaded an older launcher pass fewer than five arguments.
	if (count of arguments) < 5 then
		error "This shell has an older insights launcher loaded. Run exec zsh, then try again."
	end if

	-- Codex reviewer command to type into the middle reviewer pane.
	set reviewerCodexCommand to item 1 of arguments
	-- Claude scout command to type into the lower-left scout pane.
	set scoutClaudeCommand to item 2 of arguments
	-- Codex scout command to type into the lower-middle scout pane.
	set scoutCodexCommand to item 3 of arguments
	-- Claude consolidator command to type into the full-height right pane.
	set consolidatorCommand to item 4 of arguments
	-- ID of the pane that ran the insights command.
	set originTerminalId to item 5 of arguments

	tell application "Ghostty"
		-- The launching shell, used for the splits.
		set reviewerClaudeTerminal to missing value
		-- Window being searched for the launching pane.
		repeat with currentWindow in windows
			-- Tab being searched for the launching pane.
			repeat with currentTab in tabs of currentWindow
				-- Pane whose ID is compared with the one noted when the command started.
				repeat with currentTerminal in terminals of currentTab
					if id of currentTerminal is originTerminalId then
						set reviewerClaudeTerminal to contents of currentTerminal
						exit repeat
					end if
				end repeat
				if reviewerClaudeTerminal is not missing value then exit repeat
			end repeat
			if reviewerClaudeTerminal is not missing value then exit repeat
		end repeat
		if reviewerClaudeTerminal is missing value then
			error "The Ghostty pane that launched this insights review has closed. Run the command again from an open pane."
		end if

		-- Whether the human is using Ghostty now. Focus is restored only then, so
		-- a human who moved to another app during the launch stays there.
		set ghosttyIsFrontmost to frontmost
		if ghosttyIsFrontmost then
			-- The Ghostty window the human is looking at now.
			set frontGhosttyWindow to front window
			-- The tab the human is looking at now, which may differ from the launching tab.
			set selectedGhosttyTab to selected tab of frontGhosttyWindow
			-- The pane focus returns to after the splits, so the human's view does not move.
			set restoreTerminal to focused terminal of selectedGhosttyTab
		end if

		-- Original layout error saved until focus restoration is attempted.
		set layoutErrorMessage to missing value
		try
			-- Full-height right-hand terminal for the consolidator. It is split off
			-- first so the later down splits stay inside the two reviewer columns.
			set consolidatorTerminal to split reviewerClaudeTerminal direction right
			-- Middle terminal for the Codex reviewer.
			set reviewerCodexTerminal to split reviewerClaudeTerminal direction right
			-- Lower-left terminal for the Claude scout.
			set scoutClaudeTerminal to split reviewerClaudeTerminal direction down
			-- Lower-middle terminal for the Codex scout.
			set scoutCodexTerminal to split reviewerCodexTerminal direction down

			-- Splitting the launching pane twice leaves the consolidator with half the
			-- width, so the columns are evened out before the reviewers are made taller.
			perform action "equalize_splits" on reviewerClaudeTerminal
			perform action "resize_split:down,150" on reviewerClaudeTerminal
			perform action "resize_split:down,150" on reviewerCodexTerminal

			my runCommand(reviewerCodexTerminal, reviewerCodexCommand)
			my runCommand(scoutClaudeTerminal, scoutClaudeCommand)
			my runCommand(scoutCodexTerminal, scoutCodexCommand)
			my runCommand(consolidatorTerminal, consolidatorCommand)
		on error errorMessage number errorNumber
			set layoutErrorMessage to errorMessage
			-- Original layout error number, re-raised with the message.
			set layoutErrorNumber to errorNumber
		end try

		-- Restore the human's pane after the layout succeeds or fails, only when
		-- Ghostty was in front. A pane the human closed meanwhile is skipped so
		-- any layout error still reaches the shell.
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

-- Types one command into a Ghostty terminal and submits it.
--
-- @param {terminal} targetTerminal
--     Ghostty terminal that receives the command.
-- @param {string} commandText
--     Complete shell command to type and submit.
on runCommand(targetTerminal, commandText)
	tell application "Ghostty"
		input text commandText to targetTerminal
		send key "enter" to targetTerminal
	end tell
end runCommand

-- Opens a right-side Ghostty pane for the Scout and keeps focus on the learner pane.
--
-- @param {list} arguments
--     One-item list containing the shell command to start the Scout.
on run arguments
	-- Shell command typed into the newly created Scout terminal.
	set scoutCommand to item 1 of arguments

	tell application "Ghostty"
		activate

		if (count of windows) = 0 then
			error "Open a Ghostty terminal first."
		end if

		-- Frontmost Ghostty window that contains the learner terminal.
		set frontGhosttyWindow to front window
		-- Selected tab that contains the learner terminal.
		set selectedGhosttyTab to selected tab of frontGhosttyWindow
		-- Focused learner terminal that remains selected after the split.
		set learnerTerminal to focused terminal of selectedGhosttyTab
		-- New right-side terminal reserved for the Scout.
		set scoutTerminal to split learnerTerminal direction right

		my runCommand(scoutTerminal, scoutCommand)
		focus learnerTerminal
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

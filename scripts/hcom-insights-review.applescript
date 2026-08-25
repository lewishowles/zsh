-- Creates the four-pane insights-review layout and starts the supplied reviewer and scout commands.
--
-- @param {list} arguments
--     Four values: the Codex reviewer command, both scout commands, and their shared pair ID.
on run arguments
	-- Codex reviewer command to type into the right-hand reviewer pane.
	set reviewerCodexCommand to item 1 of arguments
	-- Claude scout command to type into the lower-left scout pane.
	set scoutClaudeCommand to item 2 of arguments
	-- Codex scout command to type into the lower-right scout pane.
	set scoutCodexCommand to item 3 of arguments
	-- Pair ID appended to the Codex reviewer command for shared tag matching.
	set insightsReviewPairId to item 4 of arguments
	-- Shell-quoted pair ID safe to append to the typed command.
	set insightsReviewPairArgument to quoted form of insightsReviewPairId

	tell application "Ghostty"
		activate

		if (count of windows) = 0 then
			error "Open a Ghostty terminal first."
		end if

		-- Frontmost Ghostty window that contains the insights-review layout.
		set currentWindow to front window
		-- Selected tab where the insights-review layout will be created.
		set selectedGhosttyTab to selected tab of currentWindow
		-- Focused terminal that anchors the four-pane layout.
		set reviewerClaudeTerminal to focused terminal of selectedGhosttyTab

		-- Right-hand terminal for the Codex reviewer.
		set reviewerCodexTerminal to split reviewerClaudeTerminal direction right
		-- Lower-left terminal for the Claude scout.
		set scoutClaudeTerminal to split reviewerClaudeTerminal direction down
		-- Lower-right terminal for the Codex scout.
		set scoutCodexTerminal to split reviewerCodexTerminal direction down

		perform action "resize_split:down,150" on reviewerClaudeTerminal
		perform action "resize_split:down,150" on reviewerCodexTerminal

		my runCommand(reviewerCodexTerminal, reviewerCodexCommand & " " & insightsReviewPairArgument)
		my runCommand(scoutClaudeTerminal, scoutClaudeCommand)
		my runCommand(scoutCodexTerminal, scoutCodexCommand)

		focus reviewerClaudeTerminal
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

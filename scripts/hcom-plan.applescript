
-- Creates the four-pane plan-review layout and starts the supplied scout commands.
-- @param arguments
--     Four values: the Codex planning command, both scout commands, and their shared pair ID.
on run arguments
	-- Codex planning command to type into the right-hand planning pane.
	set planCodexCommand to item 1 of arguments
	-- Claude scout command to type into the lower-left scout pane.
	set scoutClaudeCommand to item 2 of arguments
	-- Codex scout command to type into the lower-right scout pane.
	set scoutCodexCommand to item 3 of arguments
	-- Pair ID appended to the Codex planning command for shared tag matching.
	set planningPairId to item 4 of arguments
	-- Shell-quoted pair ID safe to append to the typed command.
	set planningPairArgument to quoted form of planningPairId

	tell application "Ghostty"
		activate

		if (count of windows) = 0 then
			error "Open a Ghostty terminal first."
		end if

		-- Ghostty window currently in front of the user.
		set currentWindow to front window
		-- Selected tab where the plan-review layout will be created.
		set selectedGhosttyTab to selected tab of currentWindow
		-- Focused terminal that anchors the four-pane layout.
		set planClaudeTerminal to focused terminal of selectedGhosttyTab

		-- Right-hand terminal for the Codex planning peer.
		set planCodexTerminal to split planClaudeTerminal direction right
		-- Lower-left terminal for the Claude scout.
		set scoutClaudeTerminal to split planClaudeTerminal direction down
		-- Lower-right terminal for the Codex scout.
		set scoutCodexTerminal to split planCodexTerminal direction down

		perform action "resize_split:down,150" on planClaudeTerminal
		perform action "resize_split:down,150" on planCodexTerminal

		my runCommand(planCodexTerminal, planCodexCommand & " " & planningPairArgument)
		my runCommand(scoutClaudeTerminal, scoutClaudeCommand)
		my runCommand(scoutCodexTerminal, scoutCodexCommand)

		focus planClaudeTerminal
	end tell
end run

-- Types one command into a Ghostty terminal and submits it.
-- @param targetTerminal
--     Terminal that receives the command.
-- @param commandText
--     Complete shell command to type and submit.
on runCommand(targetTerminal, commandText)
	tell application "Ghostty"
		input text commandText to targetTerminal
		send key "enter" to targetTerminal
	end tell
end runCommand

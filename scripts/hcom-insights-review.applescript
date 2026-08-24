on run arguments
	set reviewerCodexCommand to item 1 of arguments
	set scoutClaudeCommand to item 2 of arguments
	set scoutCodexCommand to item 3 of arguments
	set insightsReviewPairId to item 4 of arguments
	set insightsReviewPairArgument to quoted form of insightsReviewPairId

	tell application "Ghostty"
		activate

		if (count of windows) = 0 then
			error "Open a Ghostty terminal first."
		end if

		set currentWindow to front window
		set selectedGhosttyTab to selected tab of currentWindow
		set reviewerClaudeTerminal to focused terminal of selectedGhosttyTab

		set reviewerCodexTerminal to split reviewerClaudeTerminal direction right
		set scoutClaudeTerminal to split reviewerClaudeTerminal direction down
		set scoutCodexTerminal to split reviewerCodexTerminal direction down

		perform action "resize_split:down,150" on reviewerClaudeTerminal
		perform action "resize_split:down,150" on reviewerCodexTerminal

		my runCommand(reviewerCodexTerminal, reviewerCodexCommand & " " & insightsReviewPairArgument)
		my runCommand(scoutClaudeTerminal, scoutClaudeCommand)
		my runCommand(scoutCodexTerminal, scoutCodexCommand)

		focus reviewerClaudeTerminal
	end tell
end run

on runCommand(targetTerminal, commandText)
	tell application "Ghostty"
		input text commandText to targetTerminal
		send key "enter" to targetTerminal
	end tell
end runCommand

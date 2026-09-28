# @desc  List all releases for the current project
# @cat   progress
alias releases="progress release list"
# @desc  List all tasks for the current project
# @cat   progress
alias tasks="progress task list"
# @desc  Show details for the given task, or the selected next task if omitted
# @cat   progress
alias task="progress task get"
# @desc  Clean completed tasks and releases
# @cat   progress
alias clean="progress task clean --force"

# @desc  List chunks for the selected next task, or for another task with --task ID
# @cat   progress
alias chunks="progress chunk list"

# @desc  Show details for the given chunk, or the selected next chunk if omitted
# @cat   progress
alias chunk="progress chunk get"

# @desc  Complete the given task or chunk, depending on ID format
# @cat   progress
alias completed="progress complete";

# @desc  Summarise progress across all known projects
# @cat   progress
alias progress:check="progress summary"

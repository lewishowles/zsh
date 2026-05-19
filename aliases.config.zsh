# Colours for CLI output.
BLACK=$'\033[0;30m'
RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[0;33m'
BLUE=$'\033[0;34m'
PURPLE=$'\033[0;35m'
CYAN=$'\033[0;36m'
WHITE=$'\033[0;37m'
RESET_COLOUR=$'\033[0m'

# Quickly edit config / global files
alias zshrc="pushd ~ > /dev/null && code .zshrc && popd > /dev/null"
# Edit the generated global Claude instruction file.
alias claudemd="pushd ~ > /dev/null && code ~/Dev/Configuration/Agents/targets/claude/CLAUDE.md && popd > /dev/null"

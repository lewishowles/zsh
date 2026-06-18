# Colours for CLI output. Disabled when NO_COLOR is set or stdout is not a TTY.
# https://no-color.org
if [[ -t 1 ]] && [[ -z "${NO_COLOR:-}" ]]; then
	BLACK=$'\033[0;30m'
	RED=$'\033[0;31m'
	GREEN=$'\033[0;32m'
	YELLOW=$'\033[0;33m'
	BLUE=$'\033[0;34m'
	PURPLE=$'\033[0;35m'
	CYAN=$'\033[0;36m'
	WHITE=$'\033[0;37m'
	RESET_COLOUR=$'\033[0m'
else
	BLACK='' RED='' GREEN='' YELLOW='' BLUE='' PURPLE='' CYAN='' WHITE='' RESET_COLOUR=''
fi

# @desc  Open .zshrc in VS Code
# @cat   config
alias zshrc="pushd ~ > /dev/null && code .zshrc && popd > /dev/null"

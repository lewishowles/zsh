# Colours for CLI output.
RED='\033[1;31m'
PURPLE='\033[1;35m'
BLUE='\033[1;34m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
RESET_COLOUR='\033[0m'

# Quickly edit config / global files
alias zshrc="pushd ~ > /dev/null && code .zshrc && popd > /dev/null"
# Edit the global CLAUDE.md file that is referenced by projects.
alias claudemd="pushd ~ > /dev/null && code ~/Dev/Configuration/Claude/CLAUDE.md && popd > /dev/null"

# Internal helpers — not annotated, not in alias:list.
function _doctor_pass() { printf '  %s✓%s  %s\n' "$GREEN" "$RESET_COLOUR" "$1"; (( ++_pass )) }
function _doctor_fail() { printf '  %s✗%s  %s\n' "$RED" "$RESET_COLOUR" "$1"; (( ++_fail )) }
function _doctor_info() { printf '  %s·%s  %s\n' "$YELLOW" "$RESET_COLOUR" "$1" }
function _doctor_section() { printf '\n%s\n' "$1" }

# @desc  Check zsh config health: files, tools, goto paths, syntax, PATH, docs
# @cat   config
function zsh:doctor() {
	local _pass=0 _fail=0

	printf '%szsh config health check%s\n' "$CYAN" "$RESET_COLOUR"

	# --- Required files ---
	_doctor_section 'files'
	local -a required_files=(
		zshrc
		oh-my-zsh-settings.zsh
		bun-settings.zsh
		aliases.config.zsh
		aliases.packages.zsh
		aliases.project.zsh
		aliases.tools.zsh
		aliases.discovery.zsh
		aliases.doctor.zsh
	)
	local f
	for f in "${required_files[@]}"; do
		if [[ -f "$ZSH_CONFIG_ROOT/$f" ]]; then
			_doctor_pass "$f"
		else
			_doctor_fail "$f  (missing)"
		fi
	done
	# Private file — absent is safe
	if [[ -f "$ZSH_CONFIG_ROOT/aliases.private.zsh" ]]; then
		_doctor_info "aliases.private.zsh  (private — present)"
	else
		_doctor_info "aliases.private.zsh  (private — absent, safe)"
	fi

	# --- Tools ---
	_doctor_section 'tools'
	# Oh My Zsh and Powerlevel10k checked by directory, not PATH
	if [[ -d "${ZSH:-}" ]]; then
		_doctor_pass "oh-my-zsh"
	else
		_doctor_fail "oh-my-zsh  (\$ZSH not set or missing)"
	fi
	if [[ -d "${ZSH:-}/custom/themes/powerlevel10k" ]]; then
		_doctor_pass "powerlevel10k"
	else
		_doctor_fail "powerlevel10k  (expected in \$ZSH/custom/themes/)"
	fi
	# Core tools + all unique tools from @needs annotations
	local -a all_tools
	all_tools=(
		bun code vp
		$(awk '/^# @needs[[:space:]]/ {
			sub(/^# @needs[[:space:]]*/, "")
			n = split($0, a, " ")
			for (i = 1; i <= n; i++) print a[i]
		}' "$ZSH_CONFIG_ROOT"/aliases.*.zsh(N) | sort -u)
	)
	local tool
	for tool in "${(u)all_tools[@]}"; do
		if command -v "$tool" &>/dev/null; then
			_doctor_pass "$tool"
		else
			_doctor_fail "$tool  (not found on PATH)"
		fi
	done

	# --- goto: paths ---
	_doctor_section 'goto paths'
	if [[ ! -f "$ZSH_CONFIG_ROOT/aliases.private.zsh" ]]; then
		_doctor_info "aliases.private.zsh absent — no goto paths to check"
	else
		local goto_line path_raw path_expanded
		while IFS= read -r goto_line; do
			# Extract the path from: alias goto:name="cd <path>"
			# eval handles ~ expansion and quoted paths (e.g. "Visual Studio Code")
			path_raw=$(
				sed 's/^alias goto:[^=]*="cd //' <<< "$goto_line" \
				| sed 's/"[[:space:]]*$//' \
				| sed 's/\\"/"/g'
			)
			eval "path_expanded=$path_raw" 2>/dev/null
			if [[ -d "$path_expanded" ]]; then
				_doctor_pass "$path_expanded"
			else
				_doctor_fail "$path_expanded  (missing)"
			fi
		done < <(grep '^alias goto:' "$ZSH_CONFIG_ROOT/aliases.private.zsh" 2>/dev/null)
	fi

	# --- Syntax ---
	_doctor_section 'syntax'
	local -a source_files=(
		"$ZSH_CONFIG_ROOT"/aliases.*.zsh(N)
		"$ZSH_CONFIG_ROOT/oh-my-zsh-settings.zsh"
		"$ZSH_CONFIG_ROOT/bun-settings.zsh"
	)
	local err
	for f in "${source_files[@]}"; do
		if zsh -n "$f" 2>/dev/null; then
			_doctor_pass "${f:t}"
		else
			err=$(zsh -n "$f" 2>&1 | head -1)
			_doctor_fail "${f:t}  — $err"
		fi
	done

	# --- PATH ---
	_doctor_section 'path'
	if [[ ":$PATH:" == *":$HOME/.local/bin:"* ]]; then
		_doctor_pass "~/.local/bin in PATH"
	else
		_doctor_fail "~/.local/bin not in PATH"
	fi
	local -A _seen=()
	local _has_dupes=0
	local p
	for p in "${(@s[:])PATH}"; do
		if [[ -n "${_seen[$p]:-}" ]]; then
			_doctor_fail "duplicate PATH entry: $p"
			_has_dupes=1
		fi
		_seen[$p]=1
	done
	(( _has_dupes )) || _doctor_pass "no duplicate PATH entries"

	# --- Docs ---
	_doctor_section 'docs'
	if _docs_check; then
		_doctor_pass "README command table is up to date"
	else
		_doctor_fail "README command table is stale — run docs:generate"
	fi

	# --- Summary ---
	printf '\n'
	if (( _fail == 0 )); then
		printf '%s%d checks passed%s\n' "$GREEN" "$_pass" "$RESET_COLOUR"
		return 0
	else
		printf '%s%d passed%s  %s%d failed%s\n' \
			"$GREEN" "$_pass" "$RESET_COLOUR" \
			"$RED" "$_fail" "$RESET_COLOUR"
		return 1
	fi
}

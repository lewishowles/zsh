# @desc  List all annotated commands, grouped by category
# @cat   config
function alias:list() {
	local -a files
	files=("$ZSH_CONFIG_ROOT"/aliases.*.zsh(N))

	if [[ ${#files} -eq 0 ]]; then
		printf 'No alias files found in %s\n' "$ZSH_CONFIG_ROOT" >&2
		return 1
	fi

	local records
	records=$(awk '
		/^[[:space:]]*$/ { desc=""; cat=""; needs=""; next }

		/^# @desc[[:space:]]/ {
			desc = $0; sub(/^# @desc[[:space:]]*/, "", desc); next
		}
		/^# @cat[[:space:]]/ { cat = $3; next }
		/^# @needs[[:space:]]/ {
			needs = $0; sub(/^# @needs[[:space:]]*/, "", needs); next
		}

		/^alias [^=]+=/ {
			if (cat == "") { desc=""; cat=""; needs=""; next }
			name = $2; sub(/=.*/, "", name)
			print cat "\t" name "\t" desc
			desc=""; cat=""; needs=""; next
		}

		/^function [[:alnum:]]/ {
			if (cat == "") { desc=""; cat=""; needs=""; next }
			name = $2; sub(/\(\).*/, "", name); sub(/[[:space:]]+$/, "", name)
			print cat "\t" name "\t" desc
			desc=""; cat=""; needs=""; next
		}
	' "${files[@]}" | sort -t$'\t' -k1,1 -k2,2)

	if [[ -z "$records" ]]; then
		printf 'No annotated commands found.\n'
		return 0
	fi

	local prev_cat=""
	while IFS=$'\t' read -r cat name desc; do
		if [[ "$cat" != "$prev_cat" ]]; then
			[[ -n "$prev_cat" ]] && printf '\n'
			printf '%s%s%s\n' "$CYAN" "$cat" "$RESET_COLOUR"
			prev_cat="$cat"
		fi
		printf '  %-32s %s\n' "$name" "$desc"
	done <<< "$records"
}

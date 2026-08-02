#!/usr/bin/env bash
# Prompt for the credentials secrets.nix declares but the directory lacks.
#
# These come from third parties — an API key, a token pasted from a dashboard —
# so nothing can generate them. What a generator can do is know which are
# missing, say what each is for, and encrypt what you paste to the right
# recipients. Only missing credentials are asked for; to replace one, delete it
# and re-run.

set -euo pipefail

secrets_dir="$(dirname "$(dirname "$(realpath "$0")")")"
rules="$secrets_dir/secrets.nix"
tool_name="get-credentials"
# shellcheck source=lib.sh
. "$secrets_dir/scripts/lib.sh"

function usage() {
    printf '\e[1mUsage:\e[0m get-credentials.sh [\e[36m--list\e[0m] [\e[36mNAME\e[0m...]

Prompt for each credential secrets.nix declares that does not yet exist, and
encrypt it to the recipients declared there. Existing files are left untouched.

  \e[36mNAME\e[0m     ask only for these, by path or basename (\e[36mtrek-mapbox-token\e[0m)
  \e[36m--list\e[0m   show which credentials are present, without asking for any
  \e[36m--help\e[0m   show this help

Values are read from the terminal without echo, so nothing lands in your shell
history. A blank answer skips that credential, leaving it absent.\n'
}

function describe() {
    local path="$1"
    printf '%s' "${secret_help[$path]-}"
}

function declared_credentials() {
    declared_secrets | grep '^credentials/'
}

function list_credentials() {
    local path
    while IFS= read -r path; do
        if [ -e "$secrets_dir/$path" ]; then
            printf '  %s %s\n' "$mark_present" "$(basename "$path")"
        else
            printf '  %s %s\n' "$mark_absent" "$(basename "$path")"
        fi
    done < <(declared_credentials)
}

# Reads one secret without echo. Returns 1 when the answer is blank, so the
# caller can skip rather than write something the app will read as unset.
function prompt_value() {
    local path="$1" help value
    help="$(describe "$path")"
    printf '\n\e[1m%s\e[0m\n' "$path" >&2
    [ -n "$help" ] && printf '  %s\n' "$help" >&2
    printf '  value (blank to skip): ' >&2
    value="$(read_secret)"
    [ -n "$value" ] || return 1
    printf '%s' "$value"
}

function get_credential() {
    local path="$1" value
    value="$(prompt_value "$path")" || {
        printf '  %s skipped\n' "$mark_absent" >&2
        return 1
    }
    # A non-interactive stdin makes agenix use `cp /dev/stdin` as its editor.
    printf '%s' "$value" |
        (cd "$secrets_dir" && nix_run github:ryantm/agenix -- -e "$path") ||
        die "agenix failed to encrypt $path"
    printf '  %s %s\n' "$mark_wrote" "$path" >&2
    return 0
}

case "${1-}" in
    --help) usage; exit 0 ;;
    --list) list_credentials; exit 0 ;;
esac

[ -f "$rules" ] || die "no secrets.nix at $rules"
read_rules

declare -A secret_help=()
while IFS=$'\t' read -r path help; do
    [ -n "$path" ] && secret_help["$path"]="$help"
done < <(secret_descriptions)
[ -n "$(local_binding)" ] ||
    printf '%s: warning: no ~/.ssh/id_*.pub is a recipient in secrets.nix; you will not be able to decrypt these secrets\n' \
           "$tool_name" >&2

# Named credentials are asked for even if they exist elsewhere in the roster;
# with no names, every declared-but-absent one is.
wanted=()
if [ $# -gt 0 ]; then
    for name in "$@"; do
        match="$(declared_credentials | grep -E "(^|/)${name%.age}\.age$" || true)"
        [ -n "$match" ] || die "no credential named '$name' in $rules"
        [ -e "$secrets_dir/$match" ] && die "$match already exists; delete it to replace"
        wanted+=("$match")
    done
else
    while IFS= read -r path; do
        [ -e "$secrets_dir/$path" ] || wanted+=("$path")
    done < <(declared_credentials)
fi

if [ ${#wanted[@]} -eq 0 ]; then
    [ -n "${SECRETS_QUIET-}" ] ||
        printf '%s✓ nothing to do%s\n' "$colour_present" "$colour_off"
    exit 2
fi

written=0
for path in "${wanted[@]}"; do
    get_credential "$path" && written=$((written + 1)) || true
done

printf '\n'
if [ "$written" -eq 0 ]; then
    # Exit 2, not 1: skipping every prompt is a choice, and a caller treating it
    # as a failure would report a broken generator over an unanswered question.
    printf '%s~ nothing written; %d still absent%s\n' \
           "$colour_partial" "${#wanted[@]}" "$colour_off"
    exit 2
fi
printf '%s✓ %d of %d written%s\n' \
       "$colour_present" "$written" "${#wanted[@]}" "$colour_off"

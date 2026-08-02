#!/usr/bin/env bash
# Set the passwords secrets.nix declares but the directory lacks.
#
# Unlike the credentials, these are ours to choose, so each is offered a random
# value first — accept it, or type one where you need to know it (an admin login
# you will type into a web UI). Only missing passwords are asked for; to replace
# one, delete it and re-run.

set -euo pipefail

secrets_dir="$(dirname "$(dirname "$(realpath "$0")")")"
rules="$secrets_dir/secrets.nix"
tool_name="set-passwords"
# shellcheck source=lib.sh
. "$secrets_dir/scripts/lib.sh"

readonly password_length=16
# Symbols a shell, URL or YAML will not reinterpret: no quotes, backslash,
# backtick, dollar, slash, ampersand or space.
readonly password_chars='abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!#%*+,-.:=?@^_~'

function usage() {
    printf '\e[1mUsage:\e[0m set-passwords.sh [\e[36m--list\e[0m] [\e[36m--random\e[0m] [\e[36mNAME\e[0m...]

Set each password secrets.nix declares that does not yet exist, and encrypt it
to the recipients declared there. Existing files are left untouched.

  \e[36mNAME\e[0m       set only these, by path or basename (\e[36mlldap-admin-password\e[0m)
  \e[36m--random\e[0m   take the generated value for every one, without asking
  \e[36m--list\e[0m     show which passwords are present, without setting any
  \e[36m--help\e[0m     show this help

Each prompt offers a random %d-character value: press enter to take it, or type
your own. Typed values are read without echo, so nothing lands in your shell
history.\n' "$password_length"
}

function generate_password() {
    nix_run 'nixpkgs#authelia' -- crypto rand \
        --length "$password_length" --characters "$password_chars" |
        sed -n 's/^Random Value: //p'
}

function declared_passwords() {
    declared_secrets | grep '^passwords/'
}

function list_passwords() {
    local path
    while IFS= read -r path; do
        if [ -e "$secrets_dir/$path" ]; then
            printf '  %s %s\n' "$mark_present" "$(basename "$path")"
        else
            printf '  %s %s\n' "$mark_absent" "$(basename "$path")"
        fi
    done < <(declared_passwords)
}

# The value to store: the generated one unless something is typed. Prompting on
# stderr keeps stdout to the password alone.
function choose_value() {
    local path="$1" generated="$2" typed
    printf '\n\e[1m%s\e[0m\n' "$path" >&2
    [ -n "${secret_help[$path]-}" ] && printf '  %s\n' "${secret_help[$path]-}" >&2
    if [ "$use_random" = true ]; then
        printf '%s' "$generated"
        return
    fi
    printf '  press enter for \e[36m%s\e[0m, or type a password: ' "$generated" >&2
    typed="$(read_secret)"
    printf '%s' "${typed:-$generated}"
}

function set_password() {
    local path="$1" generated value
    generated="$(generate_password)" ||
        die "could not generate a password for $path"
    value="$(choose_value "$path" "$generated")"
    # A non-interactive stdin makes agenix use `cp /dev/stdin` as its editor.
    printf '%s' "$value" |
        (cd "$secrets_dir" && nix_run github:ryantm/agenix -- -e "$path") ||
        die "agenix failed to encrypt $path"
    printf '  %s %s\n' "$mark_wrote" "$path" >&2
}

use_random=false
args=()
while (($#)); do
    case "$1" in
        --help) usage; exit 0 ;;
        --list) list_passwords; exit 0 ;;
        --random) use_random=true; shift ;;
        --*) die "unknown option '$1'" ;;
        *) args+=("$1"); shift ;;
    esac
done
set -- "${args[@]+"${args[@]}"}"

[ -f "$rules" ] || die "no secrets.nix at $rules"
read_rules

declare -A secret_help=()
while IFS=$'\t' read -r path help; do
    [ -n "$path" ] && secret_help["$path"]="$help"
done < <(secret_descriptions)
[ -n "$(local_binding)" ] ||
    printf '%s: warning: no ~/.ssh/id_*.pub is a recipient in secrets.nix; you will not be able to decrypt these secrets\n' \
           "$tool_name" >&2

wanted=()
if [ $# -gt 0 ]; then
    for name in "$@"; do
        match="$(declared_passwords | grep -E "(^|/)${name%.age}\.age$" || true)"
        [ -n "$match" ] || die "no password named '$name' in $rules"
        [ -e "$secrets_dir/$match" ] && die "$match already exists; delete it to replace"
        wanted+=("$match")
    done
else
    while IFS= read -r path; do
        [ -e "$secrets_dir/$path" ] || wanted+=("$path")
    done < <(declared_passwords)
fi

if [ ${#wanted[@]} -eq 0 ]; then
    [ -n "${SECRETS_QUIET-}" ] ||
        printf '%s✓ nothing to do%s\n' "$colour_present" "$colour_off"
    exit 2
fi

for path in "${wanted[@]}"; do
    set_password "$path"
done

printf '\n%s✓ %d set%s\n' "$colour_present" "${#wanted[@]}" "$colour_off"

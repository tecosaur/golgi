#!/usr/bin/env bash
# Generate paired OIDC credentials for Authelia clients.
#
# For each app: a random client secret, encrypted to `oidc/<name>-secret.age`
# (read by the app), and its digest in `oidc/<name>-hash.txt` (read by
# `clients.nix` and served to Authelia). The two must share a name, or
# authentication fails at token exchange rather than at eval.

set -euo pipefail

secrets_dir="$(dirname "$(dirname "$(realpath "$0")")")"
rules="$secrets_dir/secrets.nix"
tool_name="make-oidc"
# shellcheck source=lib.sh
. "$secrets_dir/scripts/lib.sh"

readonly glyph_on='⬤' glyph_off='🞆'

function usage() {
    printf '\e[1mUsage:\e[0m make-oidc.sh [\e[36m--refresh\e[0m] [\e[36m--host\e[0m HOST]... (\e[36mNAME\e[0m... | \e[36m--all\e[0m)

  \e[36mNAME\e[0m          app name as it appears in site.nix, lowercased with dashes
                (e.g. \e[36mhome-assistant\e[0m); the OIDC client id in clients.nix
  \e[36m--all\e[0m         refresh every app that already has an oidc/*-hash.txt
  \e[36m-r, --refresh\e[0m regenerate existing credentials without asking, leaving
                secrets.nix untouched
  \e[36m-h, --host\e[0m    machine needing to read the secret. Repeat or comma-separate to
                name several (\e[36m-h golgi -h nucleus\e[0m, \e[36m--host golgi,nucleus\e[0m).
                Only consulted when adding a new secrets.nix entry; omit it to
                choose interactively, which requires a terminal.
  \e[36m--help\e[0m        show this help

Overwriting existing credentials is confirmed first, unless \e[36m--refresh\e[0m is given.\n'
}

# -------------------------------------------------------------------- prompts

# Restore the terminal, whether reached by the trap or called directly. Cursor
# visibility is reasserted unconditionally: an interrupt can land between the
# two, and a hidden cursor outlives the script.
function restore_tty() {
    printf '\r\e[J\e[?25h' >/dev/tty 2>/dev/null || true
    [ -n "${saved_termios:-}" ] || return 0
    local termios=$saved_termios
    saved_termios=
    stty "$termios" </dev/tty
}

function draw_options() {
    local -n opts=$1 sel=$2
    local cursor=$3 i
    for i in "${!opts[@]}"; do
        printf '\e[2K %s %s %s\r\n' \
               "$([ "$i" -eq "$cursor" ] && printf '\e[36m❯\e[0m' || printf ' ')" \
               "$([ "${sel[i]}" -eq 1 ] && printf '\e[36m%s\e[0m' "$glyph_on" || printf '%s' "$glyph_off")" \
               "${opts[i]}"
    done
    printf '\e[2K \e[2;90m↑/↓ move ⋅ SPC toggle ⋅ RET select\e[0m\r\n'
}

# Multi-select over `keys`, leaving the chosen ones in `chosen_recipients`.
# Arguments are pre-selected. Returns 2 if the user aborts.
#
# Runs with stdin and stdout on the terminal (see the call site) rather than
# in a subshell, so `stty` and the traps act on the real terminal.
function choose_recipients() {
    local -a options selected
    mapfile -t options < <(printf '%s\n' "${keys[@]}" | sort)
    local i
    for i in "${!options[@]}"; do
        [[ " $* " == *" ${options[i]} "* ]] && selected[i]=1 || selected[i]=0
    done
    chosen_recipients=()
    saved_termios="$(stty -g </dev/tty)"
    [ -n "$saved_termios" ] || die "could not read terminal settings"
    # Restore before re-raising, so the shell's SIGINT handling sees a terminal
    # already back in cooked mode.
    trap 'restore_tty; trap - INT; kill -INT $$' INT
    trap 'restore_tty; exit 143' TERM
    trap restore_tty EXIT
    stty raw -echo </dev/tty
    printf '\e[?25l'
    printf ' Which machines need to read this secret?\r\n'
    local cursor=0 drawn=0 key rest status=0
    while true; do
        [ "$drawn" -eq 1 ] && printf '\e[%dA' "$(( ${#options[@]} + 1 ))"
        draw_options options selected "$cursor"
        drawn=1
        if ! IFS= read -rsn1 key; then break; fi
        case "$key" in
            $'\e') # Arrows arrive as `\e[A`/`\e[B`, a byte at a time.
                IFS= read -rsn1 -t 0.05 rest || continue
                [ "$rest" = '[' ] || continue
                IFS= read -rsn1 -t 0.05 rest || continue
                case "$rest" in
                    A) ((cursor > 0)) && ((cursor--)) ;;
                    B) ((cursor < ${#options[@]} - 1)) && ((cursor++)) ;;
                esac ;;
            k) ((cursor > 0)) && ((cursor--)) ;;
            j) ((cursor < ${#options[@]} - 1)) && ((cursor++)) ;;
            ' ') selected[cursor]=$((1 - selected[cursor])) ;;
            a) for i in "${!options[@]}"; do selected[i]=1; done ;;
            ''|$'\n'|$'\r') break ;;
            q|$'\x03') status=2; break ;;
        esac
    done
    restore_tty
    trap - INT TERM EXIT
    [ "$status" -eq 0 ] || return "$status"
    for i in "${!options[@]}"; do
        [ "${selected[i]}" -eq 1 ] && chosen_recipients+=("${options[i]}")
    done
    return 0
}

# Ask a yes/no question, defaulting to no. With no terminal there is nobody to
# ask, and overwriting a secret is not a safe default.
function confirm() {
    local reply
    [ -t 0 ] && [ -e /dev/tty ] || return 1
    printf '%s [y/N] ' "$1" >/dev/tty
    IFS= read -r reply </dev/tty || { printf '\n' >/dev/tty; return 1; }
    [[ "$reply" == [yY]* ]]
}

# ---------------------------------------------------------------- credentials

# Credentials are only half the wiring: Authelia needs a client, and the app
# needs to read the secret. Report whichever is missing, rather than assuming
# either -- forgejo and mealie hold their secret elsewhere by design, and so
# have no module reading the .age at all.
function report_wiring() {
    local name="$1" repo="$secrets_dir/.." missing=()
    grep -rqF "oidc/$name-secret.age" "$repo/modules" 2>/dev/null ||
        missing+=("no module reads oidc/$name-secret.age")
    grep -qE "mkClient config\.site\.apps\.$name\b|name = \"$name\"" \
         "$repo/modules/auth/clients.nix" 2>/dev/null ||
        missing+=("no client in clients.nix")
    [ ${#missing[@]} -gt 0 ] || return 0
    local note
    for note in "${missing[@]}"; do
        printf '  %s %s\n' "$mark_partial" "$note"
    done
}

# Emit the secret and its digest as two NUL-terminated fields. Authelia is
# invoked once per app: it generates the pair together.
function generate_credentials() {
    local output secret digest
    output="$(nix_run 'nixpkgs#authelia' -- crypto hash generate pbkdf2 \
                  --random --random.length 72 --random.charset rfc3986)" ||
        die "authelia failed to generate credentials"
    secret="$(sed -n 's/^Random Password: //p' <<<"$output")"
    digest="$(sed -n 's/^Digest: //p' <<<"$output")"
    [ -n "$secret" ] && [ -n "$digest" ] ||
        die "could not parse authelia output:"$'\n'"$output"
    printf '%s\0%s\0' "$secret" "$digest"
}

function make_oidc() {
    local name="$1" refresh="$2" group="$3"
    local age_file="oidc/$name-secret.age" txt_file="oidc/$name-hash.txt"
    echo "$name:"
    local secret digest
    { IFS= read -r -d '' secret; IFS= read -r -d '' digest; } < <(generate_credentials)
    # agenix reads secrets.nix for the recipients, so the entry must exist first.
    [ "$refresh" = true ] || register_secret "$age_file" "$group"
    printf '%s\n' "$digest" > "$secrets_dir/$txt_file" ||
        die "could not write $secrets_dir/$txt_file"
    printf '  %s %s\n' "$mark_wrote" "$txt_file"
    # A non-interactive stdin makes agenix use `cp /dev/stdin` as its editor.
    printf '%s' "$secret" |
        (cd "$secrets_dir" && nix_run github:ryantm/agenix -- -e "$age_file") ||
        die "agenix failed to encrypt $age_file;" \
            "secrets.nix now names $age_file, which does not exist yet"
    printf '  %s %s\n' "$mark_wrote" "$age_file"
    report_wiring "$name"
}

# ----------------------------------------------------------------------- main

function parse_args() {
    local given h
    while [ $# -gt 0 ]; do
        case "$1" in
            --help) usage; exit 0 ;;
            -r|--refresh) refresh=true; shift ;;
            --all) all=true; refresh=true; shift ;;
            -h|--host)
                [ $# -ge 2 ] || die "$1 needs an argument"
                IFS=, read -ra given <<<"$2"
                for h in "${given[@]}"; do
                    [[ " ${keys[*]} " == *" $h "* ]] ||
                        die "unknown recipient '$h' (expected: ${keys[*]})"
                    recipients+=("$h")
                done
                shift 2 ;;
            -*) die "unknown option '$1'" ;;
            *) names+=("$1"); shift ;;
        esac
    done
}

# Confirm before the picker, so a declined overwrite costs nothing.
function confirm_overwrites() {
    local name existing=()
    for name in "$@"; do
        [ -e "$secrets_dir/oidc/$name-secret.age" ] && existing+=("$name")
    done
    [ ${#existing[@]} -gt 0 ] || return 0
    confirm "credentials already exist for ${existing[*]}; regenerate?" ||
        die "left unchanged"
}

# Apps with a digest but no encrypted secret cannot be refreshed as a pair, so
# they are reported rather than silently passed over: some keep the secret
# elsewhere (forgejo in its database, mealie in a bundled env file), but an
# unpaired digest is just as likely to be an oversight.
function all_refreshable() {
    local txt name unpaired=()
    for txt in "$secrets_dir"/oidc/*-hash.txt; do
        [ -e "$txt" ] || die "no existing credentials to refresh"
        name="$(basename "$txt" -hash.txt)"
        if [ -e "$secrets_dir/oidc/$name-secret.age" ]; then
            printf '%s\n' "$name"
        else
            unpaired+=("$name")
        fi
    done
    [ ${#unpaired[@]} -eq 0 ] ||
        echo "make-oidc: skipping ${unpaired[*]}: digest with no encrypted secret" >&2
}

[ -f "$rules" ] || die "no secrets.nix at $rules"
read_rules

refresh=false
all=false
recipients=()
names=()
parse_args "$@"

[ "$refresh" = true ] || confirm_overwrites "${names[@]}"

binding="$(local_binding)"
[ -n "$binding" ] ||
    echo "make-oidc: warning: no ~/.ssh/id_*.pub is a recipient in" \
         "secrets.nix; you will not be able to decrypt these secrets" >&2

# Recipients only matter when writing a secrets.nix entry; a refresh reuses
# whatever the existing entry names.
group=""
if [ "$refresh" = false ]; then
    if [ ${#recipients[@]} -eq 0 ]; then
        [ -t 0 ] && [ -e /dev/tty ] ||
            die "no terminal to choose on; pass --host (${keys[*]})"
        # This machine's own key is the only sensible pre-selection.
        local_keys=()
        [ -n "$binding" ] && local_keys=("$binding")
        choose_recipients "${local_keys[@]}" </dev/tty >/dev/tty || die "aborted"
        recipients=("${chosen_recipients[@]}")
        [ ${#recipients[@]} -gt 0 ] || die "no recipients selected"
    fi
    group="$(recipients_to_group "${recipients[@]}")"
fi

if [ "$all" = true ]; then
    [ ${#names[@]} -eq 0 ] || die "--all takes no app names"
    mapfile -t names < <(all_refreshable)
fi
[ ${#names[@]} -gt 0 ] || { usage; exit 2; }

for name in "${names[@]}"; do
    make_oidc "$name" "$refresh" "$group"
done

printf '\n%s %d credential%s generated: %s\n' "$mark_present" \
       "${#names[@]}" "$([ ${#names[@]} -eq 1 ] || echo s)" "${names[*]}"

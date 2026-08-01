#!/usr/bin/env bash
# Generate paired OIDC credentials for Authelia clients.
#
# For each app: a random client secret, encrypted to `oidc/<name>-secret.age`
# (read by the app), and its digest in `oidc/<name>-hash.txt` (read by
# `clients.nix` and served to Authelia). The two must share a name, or
# authentication fails at token exchange rather than at eval.

set -euo pipefail

secrets_dir="$(dirname "$(realpath "$0")")"
rules="$secrets_dir/secrets.nix"

readonly glyph_on='⬤' glyph_off='🞆'

# Recipients from the `let` block of secrets.nix, filled in by read_rules.
declare -a keys=()          # bindings holding a public key
declare -A alias_members=() # alias -> sorted, space-separated members

function usage() {
    cat <<'EOF'
Usage: make-oidc.sh [--refresh] [--host HOST]... (NAME... | --all)

  NAME          app name as it appears in site.nix, lowercased with dashes
                (e.g. `home-assistant`); the OIDC client id in clients.nix
  --all         refresh every app that already has an oidc/*-hash.txt
  -r, --refresh regenerate existing credentials without asking, leaving
                secrets.nix untouched
  -h, --host    machine needing to read the secret. Repeat or comma-separate to
                name several (`-h golgi -h nucleus`, `--host golgi,nucleus`).
                Only consulted when adding a new secrets.nix entry; omit it to
                choose interactively, which requires a terminal.
  --help        show this help

Overwriting existing credentials is confirmed first, unless --refresh is given.
EOF
}

function die() {
    echo "make-oidc: $*" >&2
    exit 1
}

# ---------------------------------------------------------------- secrets.nix

# Populate `keys` and `alias_members`, where `name = "ssh-..."` is a key and
# `name = [ a b c ]` an alias for a set of them.
function read_rules() {
    local line name value
    while IFS= read -r line; do
        [[ "$line" =~ ^[[:space:]]*([a-zA-Z_][a-zA-Z0-9_-]*)[[:space:]]*=[[:space:]]*(.*)$ ]] || continue
        name="${BASH_REMATCH[1]}" value="${BASH_REMATCH[2]}"
        case "$value" in
            '"ssh-'*) keys+=("$name") ;;
            '['*)
                value="${value#[}"; value="${value%%]*}"
                alias_members["$name"]="$(printf '%s\n' $value | sort -u | tr '\n' ' ')" ;;
        esac
    done < <(sed -n '/^let$/,/^in$/p' "$rules")
    [ ${#keys[@]} -gt 0 ] || die "no recipient keys found in $rules"
}

# Binding whose key this machine holds, if any. Matched on the key body alone,
# since the trailing comment is free text.
function local_binding() {
    local pub body binding
    for pub in "$HOME"/.ssh/id_*.pub; do
        [ -e "$pub" ] || continue
        body="$(cut -d' ' -f1,2 <"$pub")"
        binding="$(grep -F "$body" "$rules" | sed -n 's/^\s*\([a-z][a-zA-Z0-9_-]*\)\s*=.*/\1/p')"
        [ -n "$binding" ] || continue
        printf '%s' "$binding"
        return
    done
}

# Keys belonging to every alias, and so never a meaningful choice alone.
function ubiquitous_keys() {
    local key name
    for key in "${keys[@]}"; do
        for name in "${!alias_members[@]}"; do
            [[ " ${alias_members[$name]} " == *" $key "* ]] || continue 2
        done
        printf '%s\n' "$key"
    done
}

# Alias names, most members first, ties broken by name so the order is stable.
function alias_names_by_size() {
    local name
    for name in "${!alias_members[@]}"; do
        printf '%s %s\n' "$(wc -w <<<"${alias_members[$name]}")" "$name"
    done | sort -k1,1nr -k2,2 | cut -d' ' -f2
}

# Name the given recipients as secrets.nix would: an alias when one covers them
# exactly, otherwise the bindings themselves.
function recipients_to_group() {
    local -a wanted
    mapfile -t wanted < <(printf '%s\n' "$@" | sort -u)
    local exact implied name
    exact="$(printf '%s ' "${wanted[@]}")"
    implied="$(printf '%s\n' "${wanted[@]}" $(ubiquitous_keys) | sort -u | tr '\n' ' ')"
    for name in $(alias_names_by_size); do
        if [ "${alias_members[$name]}" = "$exact" ] ||
           [ "${alias_members[$name]}" = "$implied" ]; then
            printf '%s' "$name"
            return
        fi
    done
    if [ "${#wanted[@]}" -eq 1 ]; then
        printf '%s' "${wanted[0]}"
    else
        printf '[ %s]' "$exact"
    fi
}

# Insert `"<file>".publicKeys = <group>;`, keeping the attribute list sorted.
# An existing entry is left alone: it may name a different group deliberately.
function register_secret() {
    local file="$1" group="$2"
    if grep -qF "\"$file\"" "$rules"; then
        echo "  secrets.nix: entry already present, leaving recipients unchanged"
        return
    fi
    local entry="  \"$file\".publicKeys = $group;"
    local before
    before="$(grep -n '^\s*"[^"]*\.age"\.publicKeys' "$rules" |
              awk -v new="$file" -F'"' '$2 < new {line = $0} END {if (line) print line}' |
              cut -d: -f1)"
    if [ -n "$before" ]; then
        sed -i "${before}a\\${entry}" "$rules" || die "could not update $rules"
    else
        sed -i "0,/^{$/s//{\n${entry}/" "$rules" || die "could not update $rules"
    fi
    echo "  secrets.nix: added \`$file\` for $group"
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

# Emit the secret and its digest as two NUL-terminated fields. Authelia is
# invoked once per app: it generates the pair together.
function generate_credentials() {
    local output secret digest
    output="$(nix run 'nixpkgs#authelia' -- crypto hash generate pbkdf2 \
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
    echo "  wrote $txt_file"
    # A non-interactive stdin makes agenix use `cp /dev/stdin` as its editor.
    printf '%s' "$secret" |
        (cd "$secrets_dir" && nix run github:ryantm/agenix -- -e "$age_file") ||
        die "agenix failed to encrypt $age_file;" \
            "secrets.nix now names $age_file, which does not exist yet"
    echo "  wrote $age_file"
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

printf '\n\e[32m✓\e[0m %d credential%s generated: %s\n' \
       "${#names[@]}" "$([ ${#names[@]} -eq 1 ] || echo s)" "${names[*]}"
cat <<EOF

Add matching clients to modules/auth/clients.nix, and read the secret in the
app's module. Deploy Authelia and the app together: the digest and secret are
a matched pair, so refreshing one without the other breaks login.
EOF

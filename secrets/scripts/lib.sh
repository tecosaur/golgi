# Shared helpers for the secret generators. Sourced, not executed.
#
# Recipients are named in secrets.nix by alias, so `read_rules` parses those
# definitions and `recipients_to_group` maps a set of hosts back to one. No
# generator needs to name an alias itself.

: "${rules:?lib.sh: \$rules must name a secrets.nix}"
: "${tool_name:=secrets}"

readonly secrets_pid=$$

declare -a keys=()          # bindings holding a public key
declare -A alias_members=() # alias -> sorted, space-separated members

readonly colour_present=$'\e[32m'
readonly colour_absent=$'\e[31m'
readonly colour_partial=$'\e[33m'
readonly colour_muted=$'\e[2m'
readonly colour_off=$'\e[0m'
readonly mark_present="${colour_present}✓${colour_off}"
readonly mark_absent="${colour_absent}✗${colour_off}"
readonly mark_partial="${colour_partial}~${colour_off}"
readonly mark_wrote=$'\e[35m→\e[0m'

function die() {
    echo "$tool_name: $*" >&2
    exit 1
}

# `nix run`, less the warnings it emits about the invoking environment rather
# than about the run itself: an unset locale, and nix.conf settings this
# version does not know. Anything else on stderr is passed through.
function nix_run() {
    local status
    { nix run "$@" 2>&1 1>&3 |
        grep -vE 'setlocale: LC_ALL|^warning: unknown setting' >&2
      status=${PIPESTATUS[0]}
    } 3>&1
    return "$status"
}

# Every `"<path>.age"` secrets.nix declares, in file order.
function declared_secrets() {
    sed -n 's/^[[:space:]]*"\([^"]*\.age\)".*/\1/p' "$rules"
}

# `<path>\t<description>` for every secret that gives one. Evaluated rather than
# parsed: the rules are Nix, and agenix ignores the attribute either way.
function secret_descriptions() {
    nix eval --raw --impure --expr "
      let rules = import (/. + \"$(realpath "$rules")\");
      in builtins.concatStringsSep \"\n\" (builtins.filter (s: s != \"\")
        (builtins.attrValues (builtins.mapAttrs
          (name: v: if v ? description then name + \"\t\" + v.description else \"\")
          rules)))" 2>/dev/null || true
}

# A secret typed at the terminal, echoed as asterisks so its length is visible
# and a typo is correctable. The value goes to stdout, everything else to
# stderr, so callers can capture it. Empty when stdin is not a terminal, which
# leaves the caller's own default in play.
function read_secret() {
    local char prompt="" value="" count=0
    [ -t 0 ] || { IFS= read -r value; printf '%s' "$value"; return; }
    # Reading one character at a time means the terminal cannot turn ^C and ^D
    # into a signal and an end-of-file, so they arrive as bytes and are acted on
    # here: ^C abandons the whole run, ^D ends entry as an empty answer.
    while IFS= read -p "$prompt" -r -s -n 1 char; do
        case "$char" in
            $'\0'|$'\n') break ;;
            $'\3') printf '\n' >&2; kill -INT "$secrets_pid"; return 130 ;;
            $'\4') value=""; break ;;
            $'\177'|$'\b')
                if [ "$count" -gt 0 ]; then
                    count=$((count - 1)); prompt=$'\b \b'; value="${value%?}"
                else
                    prompt=""
                fi ;;
            *) count=$((count + 1)); prompt='*'; value+="$char" ;;
        esac
    done >&2
    printf '\n' >&2
    printf '%s' "$value"
}

# `name = "ssh-..."` is a key; `name = [ a b c ]` an alias for a set of them.
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

# Matched on the key body alone: the trailing comment is free text.
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

# Most members first, ties broken by name, so the order is stable.
function alias_names_by_size() {
    local name
    for name in "${!alias_members[@]}"; do
        printf '%s %s\n' "$(wc -w <<<"${alias_members[$name]}")" "$name"
    done | sort -k1,1nr -k2,2 | cut -d' ' -f2
}

# An alias when one covers the recipients exactly, else the bindings.
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

# Kept sorted. An existing entry is left alone: it may name a different group
# deliberately.
function register_secret() {
    local file="$1" group="$2"
    if grep -qF "\"$file\"" "$rules"; then
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
    printf '  %s secrets.nix (%s)\n' "$mark_wrote" "$group"
}

# Every recipient key but this machine's, which is the workstation these are
# run from. Generators encrypt to a node plus the workstation, so mistaking one
# for the other would put node keys where they do not belong.
function node_names() {
    local self key
    self="$(local_binding)"
    [ -n "$self" ] ||
        die "no ~/.ssh/id_*.pub is a recipient in $rules, so the machines" \
            "cannot be told apart from the workstation running this"
    for key in "${keys[@]}"; do
        [ "$key" = "$self" ] || printf '%s\n' "$key"
    done
}

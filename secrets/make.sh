#!/usr/bin/env bash
# Entry point for the secret generators in `scripts/`, which can equally be run
# directly. Adds a combined `--list` over all of them.

set -euo pipefail

secrets_dir="$(dirname "$(realpath "$0")")"
scripts_dir="$secrets_dir/scripts"
rules="$secrets_dir/secrets.nix"
tool_name="make"
# shellcheck source=scripts/lib.sh
. "$scripts_dir/lib.sh"

# command:script:summary
readonly generators=(
    "keys:init-keys.sh:service key material (Authelia, LLDAP)"
    "wireguard:init-wireguard.sh:per-node mesh keypairs"
    "oidc:make-oidc.sh:OIDC client secrets and their digests"
    "credentials:get-credentials.sh:third-party API keys and tokens, by prompt"
    "passwords:set-passwords.sh:admin logins and shared secrets, random or typed"
)

function usage() {
    printf '\e[1mUsage:\e[0m make.sh                    generate every missing secret
       make.sh <command> [args...]
       make.sh \e[36m--list\e[0m

\e[1mCommands:\e[0m\n'
    local spec command script summary
    for spec in "${generators[@]}"; do
        IFS=: read -r command script summary <<<"$spec"
        printf '  %-12s %s\n' "$command" "$summary"
    done
    printf '
Arguments after the command are passed through, so \e[36mmake.sh oidc --help\e[0m reaches
make-oidc.sh. Each script under scripts/ can also be run directly.

  \e[36m--list\e[0m   show the state of every managed secret
  \e[36m--help\e[0m   show this help

With no arguments, every gap secrets.nix declares is filled, including OIDC
credentials for an app it already names. Adding a \e[1mnew\e[0m app is the one thing that
needs asking for, since nothing yet says it should exist
(\e[36mmake.sh oidc --host HOST <app>\e[0m).\n'
}

# Listed here rather than by make-oidc.sh, whose arguments are app names. Driven
# by secrets.nix, not the directory: a deleted secret is absent from the glob and
# so would go unreported by the very check meant to catch it.
function list_oidc() {
    local secret name listed=0
    while IFS= read -r secret; do
        name="$(basename "$secret" -secret.age)"
        listed=1
        if [ ! -e "$secrets_dir/$secret" ]; then
            printf '  %s %s\n' "$mark_absent" "$name"
        elif [ -e "$secrets_dir/oidc/$name-hash.txt" ]; then
            printf '  %s %s\n' "$mark_present" "$name"
        else
            printf '  %s %s (no hash)\n' "$mark_partial" "$name"
        fi
    done < <(declared_secrets | grep '^oidc/.*-secret\.age$')
    [ "$listed" -eq 1 ] || printf '  %s none\n' "$mark_absent"
}

# Whatever no generator above claims. Matched on the directory rather than by
# asking each generator what it owns: a generator that cannot run here (no local
# recipient key, so init-wireguard cannot name the nodes) would otherwise report
# nothing and its secrets would show up as hand-managed.
function list_unrostered() {
    local secret
    while IFS= read -r secret; do
        case "$secret" in
            oidc/* | credentials/* | keys/* | passwords/*) continue ;;
        esac
        if [ -e "$secrets_dir/$secret" ]; then
            printf '  %s %s\n' "$mark_present" "$(basename "$secret")"
        else
            printf '  %s %s\n' "$mark_absent" "$(basename "$secret")"
        fi
    done < <(declared_secrets)
}

function list_all() {
    local spec command script summary listing unrostered present absent partial total
    listing=""
    for spec in "${generators[@]}"; do
        IFS=: read -r command script summary <<<"$spec"
        listing+="$(printf '\e[1m%s\e[0m: %s%s%s' \
                     "$command" "$colour_muted" "$summary" "$colour_off")"$'\n'
        if [ "$command" = "oidc" ]; then
            listing+="$(list_oidc)"$'\n'
        elif [ "$command" = "credentials" ] || [ "$command" = "passwords" ]; then
            listing+="$("$scripts_dir/$script" --list)"$'\n'
        else
            listing+="$("$scripts_dir/$script" --list)"$'\n'
        fi
    done
    unrostered="$(list_unrostered)"
    if [ -n "$unrostered" ]; then
        listing+="$(printf '\e[1mother\e[0m: %sset by hand, with no generator%s' \
                     "$colour_muted" "$colour_off")"$'\n'
        listing+="$unrostered"$'\n'
    fi
    printf '%s' "$listing"
    # Bare glyphs: the markers carry ANSI escapes, whose brackets grep would
    # read as a bracket expression.
    present="$(grep -cF '✓' <<<"$listing" || true)"
    absent="$(grep -cF '✗' <<<"$listing" || true)"
    partial="$(grep -cF '~' <<<"$listing" || true)"
    total=$((present + absent + partial))
    if [ "$absent" -gt 0 ]; then
        printf '\n%s✗ %d of %d absent%s\n' \
               "$colour_absent" "$absent" "$total" "$colour_off"
    elif [ "$partial" -gt 0 ]; then
        printf '\n%s~ %d of %d incomplete%s\n' \
               "$colour_partial" "$partial" "$total" "$colour_off"
    else
        printf '\n%s✓ all %d present%s\n' \
               "$colour_present" "$total" "$colour_off"
    fi
}

# Apps whose OIDC credentials secrets.nix declares but the directory lacks.
function missing_oidc_apps() {
    local secret
    while IFS= read -r secret; do
        [ -e "$secrets_dir/$secret" ] || basename "$secret" -secret.age
    done < <(declared_secrets | grep '^oidc/.*-secret\.age$')
}

# One generator failing does not stop the rest; each is create-only anyway.
function make_all() {
    local spec command script status failed=() made=0 apps=()
    for spec in "${generators[@]}"; do
        IFS=: read -r command script _ <<<"$spec"
        # oidc takes app names, so its gaps are filled separately below.
        [ "$command" = oidc ] && continue
        # 0 generated something, 2 had nothing to do, anything else failed.
        # `|| status=$?` keeps a non-zero exit from tripping `set -e`.
        status=0
        SECRETS_QUIET=1 "$scripts_dir/$script" || status=$?
        case "$status" in
            0) made=1 ;;
            2) ;;
            *) failed+=("$command") ;;
        esac
    done
    # make-oidc.sh is unrostered because its arguments are app names, but
    # secrets.nix names them: a declared credential with no file is a gap, and
    # the recipients are already recorded, so it needs nothing asked of it.
    mapfile -t apps < <(missing_oidc_apps)
    if [ ${#apps[@]} -gt 0 ]; then
        status=0
        "$scripts_dir/make-oidc.sh" --refresh "${apps[@]}" || status=$?
        case "$status" in
            0) made=1 ;;
            *) failed+=("oidc") ;;
        esac
    fi
    [ ${#failed[@]} -eq 0 ] || die "${failed[*]} failed; see above"
    # Skipping is a choice, not a failure: the prompts allow it, and a secret
    # left unset is reported rather than treated as done.
    # Counted from the per-secret lines only: list_all's own summary carries a
    # ✗ too, which would inflate this by one.
    local absent
    absent="$(list_all | grep -F '✗' | grep -c '^  ' || true)"
    if [ "$absent" -gt 0 ]; then
        printf '%s~ %d still unset; see make.sh --list%s\n' \
               "$colour_partial" "$absent" "$colour_off"
    elif [ "$made" -eq 0 ]; then
        printf '%s✓ nothing to do%s\n' "$colour_present" "$colour_off"
    fi
    return 0
}

function script_for() {
    local wanted="$1" spec command script
    for spec in "${generators[@]}"; do
        IFS=: read -r command script _ <<<"$spec"
        if [ "$command" = "$wanted" ]; then
            printf '%s' "$script"
            return 0
        fi
    done
    return 1
}

case "${1-}" in
    "") make_all; exit 0 ;;
    --help) usage; exit 0 ;;
    --list) list_all; exit 0 ;;
esac

command="$1"; shift
script="$(script_for "$command")" ||
    die "unknown command '$command'; try --help"
exec "$scripts_dir/$script" "$@"

#!/usr/bin/env bash
# Create the service key material under `secrets/keys/`.
#
# These sign and encrypt data that already exists, so replacing one is
# destructive: a fresh `authelia-storage` leaves the encrypted Postgres columns
# unreadable. Only missing keys are generated; rotation is a deliberate delete
# and re-run.

set -euo pipefail

secrets_dir="$(dirname "$(dirname "$(realpath "$0")")")"
keys_dir="$secrets_dir/keys"
rules="$secrets_dir/secrets.nix"
tool_name="init-keys"
# shellcheck source=lib.sh
. "$secrets_dir/scripts/lib.sh"

# name:kind. Every node holds this material: instances must share it to accept
# each other's tokens.
readonly service_keys=(
    "authelia-jwt:rand"
    "authelia-oidc-hmac:rand"
    "authelia-oidc-issuer.pem:rsa"
    "authelia-session:rand"
    "authelia-storage:rand"
    "lldap-jwt:rand"
    "lldap-key-seed:rand"
    "trek-encryption:rand"
    "multi-scrobbler-jellyfin:rand"
    "multi-scrobbler-koito:rand"
)

function usage() {
    printf '\e[1mUsage:\e[0m init-keys.sh [\e[36m--list\e[0m]

Generate any key in secrets/keys/ that does not yet exist, and register it in
secrets.nix. Existing keys are left untouched and reported as present.

  \e[36m--list\e[0m   show each key and whether it exists, without generating anything
  \e[36m--help\e[0m   show this help

To rotate a key, delete it and re-run. Read the warning in the header first:
for most of these, rotation makes existing data unreadable.\n'
}

function generate_rand() {
    nix_run 'nixpkgs#authelia' -- crypto rand --length 64 --charset alphanumeric |
        sed -n 's/^Random Value: //p'
}

function generate_rsa() {
    local dir
    dir="$(mktemp -d)"
    trap 'rm -rf "$dir"' RETURN
    # Authelia derives the public half, so only private.pem is kept.
    nix_run 'nixpkgs#authelia' -- crypto pair rsa generate --directory "$dir" >/dev/null ||
        die "authelia failed to generate an RSA keypair"
    [ -s "$dir/private.pem" ] || die "authelia wrote no private.pem"
    cat "$dir/private.pem"
}

function generate() {
    local kind="$1" value
    case "$kind" in
        rand)
            value="$(generate_rand)"
            [ -n "$value" ] || die "could not parse authelia's random value"
            printf '%s' "$value" ;;
        rsa) generate_rsa ;;
        *) die "unknown key kind '$kind'" ;;
    esac
}

function list_keys() {
    local spec name
    for spec in "${service_keys[@]}"; do
        IFS=: read -r name _ <<<"$spec"
        if [ -e "$keys_dir/$name.age" ]; then
            printf '  %s %s\n' "$mark_present" "$name.age"
        else
            printf '  %s %s\n' "$mark_absent" "$name.age"
        fi
    done
}

function init_key() {
    local name="$1" kind="$2" group="$3"
    local age_file="keys/$name.age"
    if [ -e "$keys_dir/$name.age" ]; then
        return 1
    fi
    echo "$name:"
    # agenix reads secrets.nix for the recipients, so the entry must exist first.
    register_secret "$age_file" "$group"
    # A non-interactive stdin makes agenix use `cp /dev/stdin` as its editor.
    generate "$kind" |
        (cd "$secrets_dir" && nix_run github:ryantm/agenix -- -e "$age_file") ||
        die "agenix failed to encrypt $age_file;" \
            "secrets.nix now names $age_file, which does not exist yet"
    printf '  %s %s\n' "$mark_wrote" "$age_file"
    return 0
}

case "${1-}" in
    --help) usage; exit 0 ;;
    --list) list_keys; exit 0 ;;
    "") ;;
    *) die "unknown option '$1'" ;;
esac

[ -f "$rules" ] || die "no secrets.nix at $rules"
read_rules
mkdir -p "$keys_dir"

created=0
# Word-split deliberately: node_names emits one name per line.
# shellcheck disable=SC2046
group="$(recipients_to_group "$(local_binding)" $(node_names))"
for spec in "${service_keys[@]}"; do
    IFS=: read -r name kind <<<"$spec"
    init_key "$name" "$kind" "$group" && created=$((created + 1)) || true
done

[ "$created" -gt 0 ] || exit 2
printf '\n%s %d key%s generated\n' "$mark_present" \
       "$created" "$([ "$created" -eq 1 ] || echo s)"

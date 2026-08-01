#!/usr/bin/env bash
# Create the service key material under `secrets/keys/`.
#
# Only missing keys are generated: these sign and encrypt data that already
# exists, so regenerating one is a destructive act (a fresh
# `authelia-storage` makes the encrypted Postgres columns unreadable, a fresh
# `lldap-key-seed` invalidates every key derived from it). Rotating a key is
# therefore a deliberate manual step -- delete the file and re-run -- rather
# than a flag.

set -euo pipefail

secrets_dir="$(dirname "$(realpath "$0")")"
keys_dir="$secrets_dir/keys"
rules="$secrets_dir/secrets.nix"

# name:kind:recipients. `rand` is a 64-character alphanumeric string; `rsa` an
# RSA private key in PEM form. Recipients name a binding or alias in
# secrets.nix; `all` so that the auth stack can run on any node, which requires
# every instance to hold the same key material.
readonly keys=(
    "authelia-jwt:rand:all"
    "authelia-oidc-hmac:rand:all"
    "authelia-oidc-issuer.pem:rsa:all"
    "authelia-session:rand:all"
    "authelia-storage:rand:all"
    "lldap-jwt:rand:all"
    "lldap-key-seed:rand:all"
)

function usage() {
    cat <<'EOF'
Usage: init-keys.sh [--list]

Generate any key in secrets/keys/ that does not yet exist, and register it in
secrets.nix. Existing keys are left untouched and reported as present.

  --list   show each key and whether it exists, without generating anything
  --help   show this help

To rotate a key, delete it and re-run. Read the warning in the header first:
for most of these, rotation makes existing data unreadable.
EOF
}

function die() {
    echo "init-keys: $*" >&2
    exit 1
}

# ---------------------------------------------------------------- generation

function generate_rand() {
    nix run 'nixpkgs#authelia' -- crypto rand --length 64 --charset alphanumeric |
        sed -n 's/^Random Value: //p'
}

function generate_rsa() {
    local dir
    dir="$(mktemp -d)"
    trap 'rm -rf "$dir"' RETURN
    # Writes private.pem and public.pem into --directory; only the private key
    # is stored, Authelia derives the public half.
    nix run 'nixpkgs#authelia' -- crypto pair rsa generate --directory "$dir" >/dev/null ||
        die "authelia failed to generate an RSA keypair"
    [ -s "$dir/private.pem" ] || die "authelia wrote no private.pem"
    cat "$dir/private.pem"
}

# Emit the secret for a kind on stdout.
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

# --------------------------------------------------------------- secrets.nix

# Insert `"keys/<file>".publicKeys = <group>;`, keeping the attribute list
# sorted. Mirrors make-oidc.sh, which owns the same file.
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
    echo "  secrets.nix: added \`$file\` for $group"
}

# ----------------------------------------------------------------------- main

function list_keys() {
    local spec name
    for spec in "${keys[@]}"; do
        IFS=: read -r name _ _ <<<"$spec"
        if [ -e "$keys_dir/$name.age" ]; then
            printf '  present  %s\n' "$name.age"
        else
            printf '  missing  %s\n' "$name.age"
        fi
    done
}

function init_key() {
    local name="$1" kind="$2" group="$3"
    local age_file="keys/$name.age"
    if [ -e "$keys_dir/$name.age" ]; then
        echo "$name: present, leaving unchanged"
        return 1
    fi
    echo "$name:"
    # agenix reads secrets.nix for the recipients, so the entry must exist first.
    register_secret "$age_file" "$group"
    # A non-interactive stdin makes agenix use `cp /dev/stdin` as its editor.
    generate "$kind" |
        (cd "$secrets_dir" && nix run github:ryantm/agenix -- -e "$age_file") ||
        die "agenix failed to encrypt $age_file;" \
            "secrets.nix now names $age_file, which does not exist yet"
    echo "  wrote $age_file"
    return 0
}

case "${1-}" in
    --help) usage; exit 0 ;;
    --list) list_keys; exit 0 ;;
    "") ;;
    *) die "unknown option '$1'" ;;
esac

[ -f "$rules" ] || die "no secrets.nix at $rules"
mkdir -p "$keys_dir"

created=0
for spec in "${keys[@]}"; do
    IFS=: read -r name kind group <<<"$spec"
    init_key "$name" "$kind" "$group" && created=$((created + 1)) || true
done

if [ "$created" -eq 0 ]; then
    printf '\nAll keys already present; nothing to do.\n'
else
    printf '\n\e[32m✓\e[0m %d key%s generated\n' \
           "$created" "$([ "$created" -eq 1 ] || echo s)"
    cat <<'EOF'

Deploy Authelia and LLDAP together after generating their keys: a service
started against key material its stored data was not encrypted with will fail
to read that data.
EOF
fi

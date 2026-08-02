#!/usr/bin/env bash
# Create the per-node WireGuard keypairs under `secrets/keys/`.
#
# A node's private key is its identity on the mesh, so it is encrypted to that
# node alone, and rotating one means redeploying every other node before it can
# rejoin. The public key is committed in the clear, for wireguard-mesh.nix to
# read at evaluation time.

set -euo pipefail

secrets_dir="$(dirname "$(dirname "$(realpath "$0")")")"
keys_dir="$secrets_dir/keys"
rules="$secrets_dir/secrets.nix"
tool_name="init-wireguard"
# shellcheck source=lib.sh
. "$secrets_dir/scripts/lib.sh"

function usage() {
    printf '\e[1mUsage:\e[0m init-wireguard.sh [\e[36m--list\e[0m]

Generate a WireGuard keypair for any node that does not yet have one, and
register the private key in secrets.nix. Existing keys are left untouched.

  \e[36m--list\e[0m   show each node and whether it has a key, without generating
  \e[36m--help\e[0m   show this help

Nodes are read from secrets.nix, so a new machine joins the mesh by having its
host key added there; there is no roster to update here.

To rotate a key, delete both secrets/keys/wg-<node>.age and
secrets/keys/wg-<node>.pub, re-run, then redeploy EVERY node: peers reject a
node whose public key they do not hold.\n'
}

function list_nodes() {
    local node
    while read -r node; do
        if [ -e "$keys_dir/wg-$node.age" ]; then
            printf '  %s wg-%s\n' "$mark_present" "$node"
        else
            printf '  %s wg-%s\n' "$mark_absent" "$node"
        fi
    done < <(node_names)
}

function init_node() {
    local node="$1"
    local age_file="keys/wg-$node.age" pub_file="$keys_dir/wg-$node.pub"
    if [ -e "$keys_dir/wg-$node.age" ]; then
        return 1
    fi
    echo "$node:"
    local private public group
    private="$(nix_run 'nixpkgs#wireguard-tools' -- genkey)" ||
        die "could not generate a private key for $node"
    public="$(printf '%s' "$private" | nix_run 'nixpkgs#wireguard-tools' -- pubkey)" ||
        die "could not derive the public key for $node"
    group="$(recipients_to_group "$(local_binding)" "$node")"
    # agenix reads secrets.nix for the recipients, so the entry must exist first.
    register_secret "$age_file" "$group"
    # A non-interactive stdin makes agenix use `cp /dev/stdin` as its editor.
    printf '%s' "$private" |
        (cd "$secrets_dir" && nix_run github:ryantm/agenix -- -e "$age_file") ||
        die "agenix failed to encrypt $age_file;" \
            "secrets.nix now names $age_file, which does not exist yet"
    printf '  %s %s\n' "$mark_wrote" "$age_file"
    printf '%s\n' "$public" > "$pub_file" || die "could not write $pub_file"
    printf '  %s %s\n' "$mark_wrote" "keys/wg-$node.pub"
    return 0
}

case "${1-}" in
    --help) usage; exit 0 ;;
    --list) read_rules; list_nodes; exit 0 ;;
    "") ;;
    *) die "unknown option '$1'" ;;
esac

[ -f "$rules" ] || die "no secrets.nix at $rules"
read_rules
mkdir -p "$keys_dir"

created=0
while read -r node; do
    init_node "$node" && created=$((created + 1)) || true
done < <(node_names)

[ "$created" -gt 0 ] || exit 2
printf '\n%s %d keypair%s generated\n' "$mark_present" \
       "$created" "$([ "$created" -eq 1 ] || echo s)"

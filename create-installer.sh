#!/usr/bin/env sh
self=$(realpath "$0")
if [ -z "$CONF_REPO_URL" ]; then
  repo_url=$(
    git -C "$(dirname "$self")" remote get-url origin |
    sed -E '
      /^https?:\/\//b                    # already OK → branch to end
      s#^(ssh://)?([^@]+@)?([^/:]+)[:/](.+)$#https://\3/\4#
    '
  )
  export CONF_REPO_URL="$repo_url"
fi
pushd $(mktemp -d) >/dev/null || exit 1
awk '/^#--flake\.nix--#/ {found = 1; next} found' "$self" > flake.nix
nix build --impure '.#nixosConfigurations.systemInstallerIso.config.system.build.isoImage'
outiso="$(realpath result/iso/*.iso)"
popd >/dev/null
ln -sf "$outiso" "${1:-./nixos-installer.iso}"
exit 0

#--flake.nix--#

{
  description = "Custom NixOS install media";
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
  outputs = { self, nixpkgs }: {
    nixosConfigurations = {
      systemInstallerIso = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ({ pkgs, modulesPath, ... }: {
            imports = [
              "${modulesPath}/installer/cd-dvd/installation-cd-minimal-new-kernel-no-zfs.nix"
            ];
            boot.supportedFilesystems = [ "bcachefs" ];
            environment.systemPackages = with pkgs; [
              bash
              bcachefs-tools
              btrfs-progs
              curl
              clevis
              git
              gptfdisk
              gum
              util-linux
            ];
            users.users.root.openssh.authorizedKeys.keyFiles = [
              # This is why we need `--impure` reason No. 1.
              (builtins.path {
                path = "${builtins.getEnv "HOME"}/.ssh/id_ed25519.pub";
                name = "host-root-pubkey";
              })
            ];
            systemd.services.clone-repo = {
              description = "Clone installation repository";
              after = [ "network-online.target" ];
              wants = [ "network-online.target" ];
              wantedBy = [ "multi-user.target" ];
              serviceConfig = {
                Type = "oneshot";
                # This is why we need `--impure` reason No. 2.
                ExecStart = ''
                  ${pkgs.git}/bin/git clone ${builtins.getEnv "CONF_REPO_URL"} /root/conf
                '';
              };
            };
            nix.settings.experimental-features = [
              "nix-command" "flakes"
            ];
          })
        ];
      };
    };
  };
}

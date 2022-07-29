{ config, pkgs, ... }:

{
  users.users.admin = {
    name = "admin";
    initialPassword = "1234";
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = [ "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOZZqcJOLdN+QFHKyW8ST2zz750+8TdvO9IT5geXpQVt tec@tranquillity" ];
  };
  security.sudo.wheelNeedsPassword = false;
  nix.trustedUsers = [ "@wheel" ]; # https://github.com/serokell/deploy-rs/issues/25
}

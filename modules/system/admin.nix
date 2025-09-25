{ config, pkgs, ... }:

{
  networking.firewall.allowedTCPPorts = [ 22 ];
  services.openssh.enable = true;

  users.users.admin = {
    name = "admin";
    hashedPassword = config.site.server.admin.hashedPassword;
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = config.site.server.admin.authorizedKeys;
  };
  security.sudo.wheelNeedsPassword = false;
  nix.settings.trusted-users = [ "@wheel" ]; # https://github.com/serokell/deploy-rs/issues/25
}

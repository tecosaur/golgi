{ config, lib, ... }:

with lib;

{
  networking.firewall.allowedTCPPorts = [ 22 80 443 ];

  # If I end up wanting to add plugins, see:
  # https://mdleom.com/blog/2021/12/27/caddy-plugins-nixos/
  services.caddy = mkMerge [
    {
      enable = true;
      virtualHosts."tecosaur.net".extraConfig = ''
respond "Hello, world!"
  '';
    }
    (mkIf config.services.gitea.enable {
      virtualHosts."git.tecosaur.net".extraConfig =
        "reverse_proxy localhost:${toString config.services.gitea.httpPort}";
    })
    (mkIf (builtins.hasAttr "woodpecker-server" config.services &&
           config.services.woodpecker-server.enable) {
      virtualHosts."ci.tecosaur.net".extraConfig =
        "reverse_proxy localhost:${toString config.services.woodpecker-server.httpPort}";
    })
  ];
}

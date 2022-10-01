{ config, lib, ... }:

with lib;

{
  networking.firewall.allowedTCPPorts = [ 22 80 443 ];
  networking.firewall.allowedUDPPortRanges = [ { from=443; to=443; } ];

  # If I end up wanting to add plugins, see:
  # https://mdleom.com/blog/2021/12/27/caddy-plugins-nixos/
  services.caddy = mkMerge [
    {
      enable = true;
      virtualHosts."tecosaur.net".extraConfig = ''
respond "__        __   _
\ \      / /__| | ___ ___  _ __ ___   ___
 \ \ /\ / / _ \ |/ __/ _ \| '_ ` _ \ / _ \
  \ V  V /  __/ | (_| (_) | | | | | |  __/
   \_/\_/ \___|_|\___\___/|_| |_| |_|\___|

This is an in-progress replacement for tecosaur.com, done better.

For now, you can find an increasing number of my projects on git.tecosaur.net,
this includes the setup for this server, which is being constructed using:
+ NixOS (with flakes and deploy-rs)
+ Caddy (web server)
+ Gitea (personal software forge)

In future, the following may be set up too:
+ Dendrite/Conduit (Matrix servers)
+ My TMiO blog
+ Woodpecker (continuous integration that works with Gitea)
+ Kopia (backups)
+ Koel (music streaming)
"
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

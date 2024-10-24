{ config, lib, pkgs, ... }:

with lib;

{
  networking.firewall.allowedTCPPorts = [ 80 443 ];
  networking.firewall.allowedUDPPorts = [ 443 ];

  services.caddy = {
      enable = true;
      package = pkgs.callPackage ../packages/caddy.nix {
        externalPlugins = [
          {name = "caddy-fs-git"; repo = "github.com/tecosaur/caddy-fs-git";
           version = "ef9d0ab232f4fe5d7e86312cbba45ff8afea98a1";}
        ];
      };
      virtualHosts."${config.globals.domain}".extraConfig = ''
respond "__        __   _
\ \      / /__| | ___ ___  _ __ ___   ___
 \ \ /\ / / _ \ |/ __/ _ \| '_ ` _ \ / _ \
  \ V  V /  __/ | (_| (_) | | | | | |  __/
   \_/\_/ \___|_|\___\___/|_| |_| |_|\___|

This is an in-progress replacement for tecosaur.com, done better.

For now, you can find an increasing number of my projects on code.${config.globals.domain},
this includes the setup for this server, which is being constructed using:
+ NixOS (with flakes and deploy-rs)
+ Authelia and LLDAP (for authentication)
+ Caddy (web server)
+ Forgejo (personal software forge)
+ Syncthing (cross-device folder sync tool)
+ Headscale (virtual network)
+ MicroBin (personal pastebin + url shortener)

In future, the following may be set up too:
+ Dendrite/Conduit (Matrix servers)
+ My TMiO blog
+ Kopia (backups)
+ Koel (music streaming)
"
  '';
      virtualHosts."status.${config.globals.domain}".extraConfig =
        "redir https://stats.uptimerobot.com/ah8wBH3PYy 302";
  };

  users.users.caddy = {
    extraGroups =
      lib.optional config.services.syncthing.enable config.services.syncthing.user ++
      lib.optional config.services.forgejo.enable   config.services.forgejo.user;
  };
}

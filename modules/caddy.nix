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
          {name = "replace-response"; repo = "github.com/caddyserver/replace-response";
           version = "f92bc7d0c29d0588f91f29ecb38a0c4ddf3f85f8";}
        ];
        vendorHash = "sha256-SFepy3A/Dxqnke78lwzxGmtctkUpgnDU3uVhCxLQAQ0=";
      };
      virtualHosts."${config.site.domain}".extraConfig = ''
@assets path /favicon.ico
file_server @assets {
  root /etc/site-assets
}
respond / "__        __   _
\ \      / /__| | ___ ___  _ __ ___   ___
 \ \ /\ / / _ \ |/ __/ _ \| '_ ` _ \ / _ \
  \ V  V /  __/ | (_| (_) | | | | | |  __/
   \_/\_/ \___|_|\___\___/|_| |_| |_|\___|

This is an in-progress replacement for tecosaur.com, done better.

For now, you can find an increasing number of my projects on ${config.site.apps.forgejo.subdomain}.${config.site.domain},
this includes the setup for this server, which is being constructed using:
+ NixOS (with flakes and deploy-rs)
${concatStringsSep "\n" (map (app: "+ ${app.name} (${app.description})")
  (builtins.filter (app: app.enabled) (builtins.attrValues config.site.apps)))}

In future, the following may be set up too:
+ Dendrite/Conduit (Matrix servers)
+ My TMiO blog
+ Kopia (backups)
+ Koel (music streaming)
"
  '';
  };

  environment.etc."site-assets/favicon.ico" = {
    source = ../assets/site/favicon.ico;
    mode = "0444";
  };

  users.users.caddy = {
    extraGroups =
      lib.optional config.services.syncthing.enable config.services.syncthing.user ++
      lib.optional config.services.forgejo.enable   config.services.forgejo.user;
  };
}

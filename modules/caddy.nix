{ config, lib, ... }:

with lib;

{
  networking.firewall.allowedTCPPorts = [ 80 443 ];
  networking.firewall.allowedUDPPorts = [ 443 ];

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
+ Forgejo (personal software forge)

In future, the following may be set up too:
+ Dendrite/Conduit (Matrix servers)
+ My TMiO blog
+ Kopia (backups)
+ Koel (music streaming)
"
  '';
    }
    (mkIf config.services.gitea.enable {
      virtualHosts."git.tecosaur.net".extraConfig =
      ''
@not_tec {
    not path /tec/*
    not header Cookie *caddy_tec_redirect=true*
}
handle @not_tec {
    reverse_proxy localhost:${toString config.services.gitea.settings.server.HTTP_PORT} {
        @404 status 404
        handle_response @404 {
            header +Set-Cookie "caddy_tec_redirect=true; Max-Age=5"
            redir * /tec{uri}
        }
    }
}
@tec_redirect {
    path /tec/*
    header Cookie *caddy_tec_redirect=true*
}
handle @tec_redirect {
    reverse_proxy localhost:${toString config.services.gitea.settings.server.HTTP_PORT} {
        @404 status 404
        handle_response @404 {
            header +Set-Cookie "caddy_tec_redirect=true; Max-Age=0"
            handle_path /tec/* {
                redir * {uri}
            }
        }
    }
}
handle {
    reverse_proxy localhost:${toString config.services.gitea.settings.server.HTTP_PORT}
}
'';
    })
  ];
}

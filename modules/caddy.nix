{ config, lib, pkgs, ... }:

with lib;

let
  domain = "tecosaur.net";
in {
  networking.firewall.allowedTCPPorts = [ 80 443 ];
  networking.firewall.allowedUDPPorts = [ 443 ];

  services.caddy = mkMerge [
    {
      enable = true;
      package = pkgs.callPackage ../packages/caddy.nix {
        externalPlugins = [
          {name = "caddy-fs-git"; repo = "github.com/tecosaur/caddy-fs-git";
           version = "ef9d0ab232f4fe5d7e86312cbba45ff8afea98a1";}
        ];
      };
      virtualHosts."${domain}".extraConfig = ''
respond "__        __   _
\ \      / /__| | ___ ___  _ __ ___   ___
 \ \ /\ / / _ \ |/ __/ _ \| '_ ` _ \ / _ \
  \ V  V /  __/ | (_| (_) | | | | | |  __/
   \_/\_/ \___|_|\___\___/|_| |_| |_|\___|

This is an in-progress replacement for tecosaur.com, done better.

For now, you can find an increasing number of my projects on code.${domain},
this includes the setup for this server, which is being constructed using:
+ NixOS (with flakes and deploy-rs)
+ Caddy (web server)
+ Forgejo (personal software forge)
+ Syncthing (cross-device folder sync tool)

In future, the following may be set up too:
+ Dendrite/Conduit (Matrix servers)
+ My TMiO blog
+ Kopia (backups)
+ Koel (music streaming)
"
  '';
    virtualHosts."blog.${domain}".extraConfig = ''
redir /tmio /tmio/
handle_path /tmio/* {
    file_server {
        fs git ${config.services.forgejo.stateDir}/repositories/tec/this-month-in-org.git html
    }
}
handle {
    respond 404
}
  '';
    }
    (mkIf config.services.syncthing.enable {
      virtualHosts."syncthing.${domain}".extraConfig =
        ''
reverse_proxy ${config.services.syncthing.guiAddress} {
    header_up Host {upstream_hostport}
}
'';
    })
    (mkIf config.services.syncthing.enable {
      virtualHosts."public.${domain}".extraConfig =
        ''
        root * ${config.services.syncthing.dataDir}/public/.build
        file_server
        '';
    })
    (mkIf config.services.forgejo.enable {
      virtualHosts."git.tecosaur.net".extraConfig = "redir https://code.${domain}{uri} 301";
    })
    (mkIf config.services.forgejo.enable {
      virtualHosts."code.${domain}".extraConfig =
      ''
@not_tec {
    not path /tec/*
    not header Cookie *caddy_tec_redirect=true*
}
handle @not_tec {
    reverse_proxy localhost:${toString config.services.forgejo.settings.server.HTTP_PORT} {
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
    reverse_proxy localhost:${toString config.services.forgejo.settings.server.HTTP_PORT} {
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
    reverse_proxy localhost:${toString config.services.forgejo.settings.server.HTTP_PORT}
}
'';
    })
  ];

  users.users.caddy = {
    extraGroups =
      lib.optional config.services.syncthing.enable config.services.syncthing.user ++
      lib.optional config.services.forgejo.enable   config.services.forgejo.user;
  };
}

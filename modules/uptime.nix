{ config, lib, pkgs, ... }:

let
  kuma-domain = "${config.site.apps.uptime.subdomain}.${config.site.domain}";
in
{
  site.apps.uptime.enabled = true;

  services.uptime-kuma = {
    enable = true;
    settings.PORT = "3001";
  };

  services.caddy.virtualHosts."${kuma-domain}".extraConfig =
    ''
    @public path /status/* /assets/* /icon.svg /manifest.json  /api/status-page/*
    @unauth_home {
        path /
        not header Cookie *authelia_session*
    }
    route @unauth_home {
        redir https://${kuma-domain}/status/site
    }
    route @public {
        reverse_proxy :${config.services.uptime-kuma.settings.PORT}
    }
    route * {
        import auth
        reverse_proxy :${config.services.uptime-kuma.settings.PORT}
    }
    '';
}

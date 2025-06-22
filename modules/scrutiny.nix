{ config, lib, pkgs, ... }:

{
  site.apps.scrutiny.enabled = true;

  services.scrutiny = {
    enable = true;
    settings = {
      web.listen.port = config.site.apps.scrutiny.port;
    };
  };

  services.caddy.virtualHosts."${config.site.apps.scrutiny.subdomain}.${config.site.domain}".extraConfig =
    ''
    reverse_proxy :${toString config.site.apps.scrutiny.port}
    '';
}

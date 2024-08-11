{ config, lib, pkgs, ... }:

let
  headscale-domain = "headscale.${config.globals.domain}";
  port = 8174;
in {
  services.headscale = {
      enable = true;
      port = port;
      settings = {
        server_url = "https://${headscale-domain}:${toString port}";
        dns_config.base_domain = headscale-domain;
        ip_prefixes = [ "fd7a:115c:a1e0::/48" "100.64.0.0/10" ];
      };
  };
  environment.systemPackages = [ config.services.headscale.package ];
  services.caddy.virtualHosts."${headscale-domain}".extraConfig =
    ''
    reverse_proxy localhost:${toString config.services.headscale.port}
    '';
}

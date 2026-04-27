{ config, lib, pkgs, ... }:

let
  cloudflare-bypass-stub = if config.site.cloudflare-bypass-subdomain != null then
    " ${config.site.cloudflare-bypass-subdomain}" else "";
  dynamicdns-config = if config.site.server.authoritative then
    ''
    domains {
            ${config.site.domain} @ * _${config.site.server.host}${cloudflare-bypass-stub}
    }
    ip_source simple_http https://icanhazip.com
    ''
    else
    ''
    domains {
            ${config.site.domain} _${config.site.server.host}
    }
    ip_source simple_http https://icanhazip.com
    versions ${lib.strings.concatStringsSep " " config.site.server.ipversions}
    dynamic_domains
    '';
in {
  networking.firewall.allowedTCPPorts = [ 80 443 ];
  networking.firewall.allowedUDPPorts = [ 443 ];

  age.secrets.cloudflare-api-env = {
    owner = "caddy";
    group = "users";
    file = ../secrets/cloudflare-api-env.age;
  };

  services.caddy = {
      enable = true;
      package = pkgs.caddy.withPlugins {
        plugins = [
          "github.com/caddy-dns/cloudflare@v0.2.4"
          "github.com/mholt/caddy-dynamicdns@v0.0.0-20251231002810-1af4f8876598"
          "github.com/tecosaur/caddy-fs-git@v0.0.0-20240109175104-ef9d0ab232f4"
          "github.com/caddyserver/replace-response@v0.0.0-20250618171559-80962887e4c6"
        ];
        hash = "sha256-/+j704hNqotwGuWdepMgDPEmbPkOSInEW7JAJQKRcTA=";
      };
      globalConfig =
        ''
        acme_dns cloudflare {env.CLOUDFLARE_AUTH_TOKEN}
        dynamic_dns {
                provider cloudflare {env.CLOUDFLARE_AUTH_TOKEN}
                ${dynamicdns-config}
        }
        '';
      # A Caddy snippet that can be imported to enable Authelia in front of a service
      # Taken from https://www.authelia.com/integration/proxies/caddy/#subdomain
      extraConfig = if builtins.hasAttr "main" config.services.authelia.instances &&
                       config.services.authelia.instances.main.enable then ''
          (auth) {
              forward_auth :${toString config.site.apps.authelia.port} {
                  uri /api/authz/forward-auth
                  copy_headers Remote-User Remote-Groups Remote-Email Remote-Name
              }
          }
        '' else ''
          (auth) {
              forward_auth https://${config.site.apps.authelia.subdomain}.${config.site.domain} {
                  header_up Host  {upstream_hostport}
                  uri /api/authz/forward-auth?rd=https://${config.site.apps.authelia.subdomain}.${config.site.domain}
                  copy_headers Remote-User Remote-Groups Remote-Email Remote-Name
              }
          }
        '';
      virtualHosts."*.${config.site.domain}" = lib.mkIf config.site.server.authoritative {
        extraConfig =
          ''
          respond "In the beginning, there was darkness." 404
          '';
      };
  };

  systemd.services.caddy.serviceConfig = {
    EnvironmentFile = config.age.secrets.cloudflare-api-env.path;
  };
}

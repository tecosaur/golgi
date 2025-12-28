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
  authelia-uri = if builtins.hasAttr "main" config.services.authelia.instances &&
                    config.services.authelia.instances.main.enable then
    "localhost:${toString config.site.apps.authelia.port}"
  else
    "${config.site.apps.authelia.subdomain}.${config.site.domain}";
in {
  networking.firewall.allowedTCPPorts = [ 80 443 ];
  networking.firewall.allowedUDPPorts = [ 443 ];

  age.secrets.cloudflare-api-env = {
    owner = "caddy";
    group = "users";
    file = ../secrets/cloudflare-api-env.age;
  };

  # FIXME: Dep issue
  # I'd like to upgrade caddy to 2.10, but then I need to bump
  # dynamicdns so that libdns works, and that produces this error:
  #   go: github.com/caddyserver/caddy/v2/modules/caddyhttp tested by
  #       github.com/caddyserver/caddy/v2/modules/caddyhttp.test imports
  #       github.com/prometheus/client_golang/prometheus/testutil imports
  # *     github.com/kylelemons/godebug/diff: missing go.sum entry for module providing package github.com/kylelemons/godebug/diff (imported by github.com/prometheus/client_gola  ng/prometheus/testutil); to add:
  #       go get github.com/prometheus/client_golang/prometheus/testutil@v1.22.0

  services.caddy = {
      enable = true;
      package = pkgs.caddy.withPlugins {
        plugins = [
          "github.com/caddy-dns/cloudflare@v0.2.2"
          "github.com/mholt/caddy-dynamicdns@v0.0.0-20251020155855-d8f490a28db6"
          "github.com/tecosaur/caddy-fs-git@v0.0.0-20240109175104-ef9d0ab232f4"
          "github.com/caddyserver/replace-response@v0.0.0-20250618171559-80962887e4c6"
        ];
        hash = "sha256-9pDBSPrGSOsFNg121EyhBxceeXojU7LjbfXp09eT6co=";
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
      extraConfig = ''
          (auth) {
              forward_auth ${authelia-uri} {
                  uri /api/authz/forward-auth
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

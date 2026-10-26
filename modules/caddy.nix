{ config, lib, pkgs, ... }:

{
  networking.firewall.allowedTCPPorts = [ 80 443 ];
  networking.firewall.allowedUDPPorts = [ 443 ];

  services.caddy = {
      enable = true;
      package = pkgs.caddy.withPlugins {
        plugins = [
          "github.com/caddy-dns/bunny@v1.2.0"
          "github.com/tecosaur/caddy-fs-git@v0.0.0-20240109175104-ef9d0ab232f4"
          "github.com/caddyserver/replace-response@v0.0.0-20250618171559-80962887e4c6"
        ];
        hash = "sha256-+W4e8tGbjwN3G+fI4crsCyoGPEITxpTzbPdQL0wA+xQ=";
      };
      globalConfig =
        ''
        # The challenge check finds the zone's nameservers through these, not
        # the system resolver, whose cache can trail a nameserver change by
        # a day and wait on a provider no longer authoritative.
        cert_issuer acme {
            dns bunny {file./run/credentials/caddy.service/bunny}
            resolvers 1.1.1.1 8.8.8.8
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

  # The Bunny key dns-pooler writes the zone with, for ACME DNS challenges;
  # dns-pooler keeps the records, so Caddy no longer updates any itself.
  systemd.services.caddy.serviceConfig.LoadCredential =
    [ "bunny:${config.age.secrets.bunny-dns-key.path}" ];
}

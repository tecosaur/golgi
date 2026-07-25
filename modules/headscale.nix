{ config, lib, pkgs, ... }:

let
  headscale-domain = "${config.site.apps.headscale.subdomain}.${config.site.domain}";
  headscale-port = config.site.apps.headscale.port;
  headplane-port = config.site.apps.headscale.headplane-port;
  magicdns-domain = "${config.site.apps.headscale.magicdns-subdomain}.${config.site.domain}";
  headscale-config-copy = (pkgs.formats.yaml { }).generate "headscale.yaml" config.services.headscale.settings;
in {
  site.apps.headscale.enabled = true;

  age.secrets = {
    headscale-oidc = {
      owner = "headscale";
      file = ../secrets/headscale-oidc-secret.age;
    };
    headplane-oidc = {
      owner = "headscale";
      file = ../secrets/headplane-oidc-secret.age;
    };
  };

  networking.firewall.allowedUDPPorts = [ 41641 3478 ];

  services.headscale = {
      enable = true;
      port = headscale-port;
      settings = {
        server_url = "https://${headscale-domain}";
        dns = {
          base_domain = magicdns-domain;
          override_local_dns = false;
        };
        ip_prefixes = [ "fd7a:115c:a1e0::/48" "100.64.0.0/10" ];
        oidc = {
          issuer = "https://${config.site.apps.authelia.subdomain}.${config.site.domain}";
          client_id = "headscale";
          client_secret_path = config.age.secrets.headscale-oidc.path;
          scope = [ "openid" "profile" "email" "groups" ];
          allowed_groups = [ "headscale" ];
          pkce = {
            enabled = true;
            method = "S256";
          };
          extra_params = {
            domain_hint = config.site.domain;
          };
        };
        policy = {
          mode = "database";
          path = "${config.services.headscale.settings.database.sqlite.path}";
        };
      };
  };

  systemd.services.headscale = lib.mkIf (config.services.authelia.instances ? main
                                         && config.services.authelia.instances.main.enable) {
    after = lib.mkAfter [ "authelia-main.target" ];
    wants = lib.mkAfter [ "authelia-main.target" ];
  };

  services.headplane = {
    enable = true;
    settings = {
      server = {
        host = "127.0.0.1";
        port = headplane-port;
        base_url = "https://${headscale-domain}";
        cookie_secret_path = "/var/lib/headplane/cookie_secret";
        cookie_secure = true;
        data_path = "/var/lib/headplane";
      };
      headscale = {
        url = "https://${headscale-domain}";
        api_key_path = "/var/lib/headplane/api_key";
      };
      integration = {
        agent = {
          enabled = true;
          host_name = "headplane-agent";
          work_dir = "/var/lib/headplane/agent";
        };
        proc.enabled = true;
      };
      oidc = {
        issuer = "https://${config.site.apps.authelia.subdomain}.${config.site.domain}";
        client_id = "headplane";
        client_secret_path = config.age.secrets.headplane-oidc.path;
        disable_api_key_login = true;
        token_endpoint_auth_method = "client_secret_basic";
        use_pkce = true;
      };
    };
  };

  systemd.services.headplane.preStart = ''
    umask 077
    if [ ! -s /var/lib/headplane/cookie_secret ]; then
        head -c 32 /dev/urandom | base64 | head -c 32 > /var/lib/headplane/cookie_secret
    fi
    if [ ! -s /var/lib/headplane/api_key ]; then
        ${lib.getExe pkgs.headscale} apikeys create -e 99y > /var/lib/headplane/api_key
    fi
  '';

  environment.systemPackages = [ config.services.headscale.package ];
  services.caddy.virtualHosts."${headscale-domain}".extraConfig =
    ''
    @ui path /admin /admin/*
    @browser-root {
        header User-Agent *Mozilla*
        path /
    }
    root ${config.site.assets}/headscale
    route {
        redir @browser-root /admin/
        handle /admin/favicon.ico {
             uri strip_prefix /admin
             file_server
        }
        reverse_proxy @ui :${toString headplane-port}
        file_server /favicon.ico
        reverse_proxy :${toString headscale-port}
    }
    '';
}

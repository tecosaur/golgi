{ config, lib, pkgs, ... }:

let
  headscale-domain = "${config.site.apps.headscale.subdomain}.${config.site.domain}";
  headscale-port = config.site.apps.headscale.port;
  headplane-port = config.site.apps.headscale.headplane-port;
  magicdns-domain = "${config.site.apps.headscale.magicdns-subdomain}.${config.site.domain}";
  headscale-config-copy = (pkgs.formats.yaml { }).generate "headscale.yaml" config.services.headscale.settings;
  headplane-pkg = pkgs.callPackage ../packages/headplane.nix { };
in {
  site.apps.headscale.enabled = true;

  age.secrets.headscale-oidc = {
    owner = "headscale";
    group = "users";
    file = ../secrets/headscale-oidc-secret.age;
  };

  age.secrets.headplane-env = {
    owner = "headscale";
    group = "users";
    file = ../secrets/headplane-env.age;
  };

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

  systemd.services.headscale.serviceConfig = {
    ExecStartPre = "/bin/sh -c 'touch -a ${config.services.headscale.settings.policy.path}'";
  };

  systemd.services.headplane = {
    description = "Headscale UI";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      User = config.services.headscale.user;
      Group = config.services.headscale.group;
      ExecStart = "${headplane-pkg}/bin/headplane";
      # Workaround for <https://github.com/tale/headplane/issues/48>
      ExecStartPre = "/bin/sh -c 'cp ${headscale-config-copy} /tmp/headscale.yaml; chmod u+w /tmp/headscale.yaml'";
      Environment = [
        "HEADSCALE_INTEGRATION=proc"
        # "CONFIG_FILE=${headscale-config-copy}"
        "CONFIG_FILE=/tmp/headscale.yaml"
        "PORT=${toString headplane-port}"
        "DISABLE_API_KEY_LOGIN=true"
      ];
      # `COOKIE_SECRET` and `ROOT_API_KEY`
      EnvironmentFile = config.age.secrets.headplane-env.path;
      # Restart = "always";
    };
  };

  services.authelia.instances.main.settings = {
    identity_providers.oidc = {
      authorization_policies.headscale = {
        default_policy = "deny";
        rules = [
          {
            policy = "two_factor";
            subject = "group:headscale";
          }
        ];
      };
      clients = [
        {
          client_id = "headscale";
          client_name = "Headscale";
          client_secret = "$argon2id$v=19$m=65536,t=3,p=4$JxZLRd3W145f3uB3D2UVqw$kJVGMuaLzESu9kWDYE8p8mnM2qRRAiaLgAI0vJaCu5k";
          authorization_policy = "headscale";
          public = false;
          consent_mode = "implicit";
          redirect_uris = [
            "https://${headscale-domain}/oidc/callback"
            "https://${headscale-domain}/admin/oidc/callback"
          ];
          scopes = [ "openid" "email" "profile" "groups" ];
          userinfo_signed_response_alg = "none";
          token_endpoint_auth_method = "client_secret_basic";
        }
      ];
    };
  };

  environment.systemPackages = [ config.services.headscale.package ];
  services.caddy.virtualHosts."${headscale-domain}".extraConfig =
    ''
    @ui path /admin /admin/*
    reverse_proxy @ui :${toString headplane-port}
    reverse_proxy :${toString headscale-port}
    '';
}

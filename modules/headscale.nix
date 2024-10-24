{ config, lib, pkgs, ... }:

let
  headscale-domain = "headscale.${config.globals.domain}";
  port = 8174;
in {
  age.secrets.headscale-oidc = {
    owner = "headscale";
    group = "users";
    file = ../secrets/headscale-oidc-secret.age;
  };

  services.headscale = {
      enable = true;
      port = port;
      settings = {
        server_url = "https://${headscale-domain}";
        dns.base_domain = "clients.${headscale-domain}";
        ip_prefixes = [ "fd7a:115c:a1e0::/48" "100.64.0.0/10" ];
        oidc = {
          issuer = "https://auth.${config.globals.domain}";
          client_id = "headscale";
          client_secret_path = config.age.secrets.headscale-oidc.path;
          extra_params = {
            domain_hint = "${config.globals.domain}";
          };
        };
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
          redirect_uris = [ "https://${headscale-domain}/oidc/callback" ];
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
    reverse_proxy localhost:${toString config.services.headscale.port}
    '';
}

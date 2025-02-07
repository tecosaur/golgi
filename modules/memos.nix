{ config, lib, pkgs, ... }:

let
  memos-pkg = pkgs.callPackage ../packages/memos.nix { };
  memos-domain = "${config.site.apps.memos.subdomain}.${config.site.domain}";
  memos-port = toString config.site.apps.memos.port;
in {
  site.apps.memos.enabled = true;

  systemd.services.memos = {
    description = "memos";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    serviceConfig = {
      Type = "simple";
      ExecStart = "${memos-pkg}/bin/memos --mode prod --data /var/lib/memos --port ${memos-port}";
      Restart = "always";
      RestartSec = 5;
      User = "memos";
      Group = "memos";
      StateDirectory = "memos";
      StandardOutput = "journal";
    };
  };

  users.users.memos = {
    isSystemUser = true;
    group = "memos";
  };

  users.groups.memos = { };

  services.authelia.instances.main.settings = {
    identity_providers.oidc = {
      authorization_policies.memos = {
        default_policy = "deny";
        rules = [
          {
            policy = "one_factor";
            subject = "group:${config.site.apps.memos.user-group}";
          }
          {
            policy = "two_factor";
            subject = "group:${config.site.apps.memos.admin-group}";
          }
        ];
      };
      clients = [
        {
          client_id = "memos";
          client_name = "Memos";
          client_secret = "$argon2id$v=19$m=65536,t=3,p=4$5SHxB5qqWhPiYFeZ/cUXQQ$u1lemwNPR6FCopfiR65/jAt0DOfa5GXeKd/YqkD8l7M";
          authorization_policy = "memos";
          public = false;
          consent_mode = "implicit";
          redirect_uris = [ "https://${memos-domain}/auth/callback" ];
          scopes = [ "openid" "email" "profile" ];
          userinfo_signed_response_alg = "none";
          token_endpoint_auth_method = "client_secret_post";
          grant_types = [ "authorization_code" ];
        }
      ];
    };
  };

  services.caddy.virtualHosts."${memos-domain}".extraConfig =
    "reverse_proxy :${memos-port}";
}

{ config, lib, pkgs, ... }:

let
  mealie-domain = "${config.site.apps.mealie.subdomain}.${config.site.domain}";
  mealie-user = "mealie";
in {
  site.apps.mealie.enabled = true;

  age.secrets.mealie-credentials = {
    owner = mealie-user;
    group = "users";
    file = ../secrets/mealie-credentials.env;
  };

  services.mealie = {
    enable = true;
    package = pkgs.callPackage ../packages/mealie.nix { }; # Newer version of mealie
    port = config.site.apps.mealie.port;
    settings = {
      ALLOW_SIGNUP = "false";
      MAX_WORKERS = 1;
      WEB_CONCURRENCY = 1;
      BASE_URL = "https://${mealie-domain}";
      TOKEN_TIME = 2200;
      DB_ENGINE = "postgres";
      DATA_DIR = config.site.apps.mealie.dir;
      CRF_MODEL_PATH = "${config.site.apps.mealie.dir}/model.crfmodel";
      POSTGRES_URL_OVERRIDE = "postgresql://${mealie-user}:@localhost/${mealie-user}?host=/run/postgresql";
      OIDC_AUTH_ENABLED = "true";
      OIDC_AUTO_REDIRECT = "false"; # Currently `true` is bugged :(
      OIDC_CLIENT_ID = "mealie";
      OIDC_CONFIGURATION_URL = "https://${config.site.apps.authelia.subdomain}.${config.site.domain}/.well-known/openid-configuration";
      OIDC_SIGNUP_ENABLED = "true";
      OIDC_USER_GROUP = config.site.apps.mealie.user-group;
      OIDC_ADMIN_GROUP = config.site.apps.mealie.admin-group;
      LOG_LEVEL = "DEBUG";
    };
    credentialsFile = config.age.secrets.mealie-credentials.path;
  };

  systemd.services.mealie = let
    dependencies = [ "postgresql.service" ];
  in {
    after = dependencies;
    requires = dependencies;
    serviceConfig.User = mealie-user;
    serviceConfig.DynamicUser = lib.mkForce false;
  };

  services.postgresql = {
    enable = true;
    ensureDatabases = [ mealie-user ];
    ensureUsers = [
      { name = mealie-user;
        ensureDBOwnership = true;
      }
    ];
  };

  users.users.${mealie-user} = {
    group = mealie-user;
    isSystemUser = true;
  };
  users.groups.${mealie-user} = {};

  services.authelia.instances.main.settings = {
    identity_providers.oidc = {
      # authorization_policies.mealie = {
      #   default_policy = "one_factor";
        # rules = [
        #   {
        #     policy = "two_factor";
        #     subject = [ [ "group:${config.site.apps.mealie.user-group}"
        #                   "group:${config.site.apps.mealie.admin-group}" ] ];
        #   }
        # ];
      # };
      clients = [
        {
          client_id = "mealie";
          client_name = "Mealie";
          client_secret = "$argon2id$v=19$m=65536,t=3,p=4$hTubW+z8HklfQlm2mi8oPA$cFVnkx8aYkDkPlSJUcHo5F88vCfN/ija/U44sEqOa64";
          # authorization_policy = "mealie";
          authorization_policy = "one_factor";
          public = false;
          consent_mode = "implicit";
          redirect_uris = [ "https://${mealie-domain}/login"
                            "http://localhost:${toString config.site.apps.mealie.port}/login" ];
          # require_pkce = true;
          pkce_challenge_method = "S256";
          scopes = [ "openid" "email" "profile" "groups" ];
          userinfo_signed_response_alg = "none";
          token_endpoint_auth_method = "client_secret_basic";
          grant_types = [ "authorization_code" ];
        }
      ];
    };
  };

  services.caddy.virtualHosts."${mealie-domain}".extraConfig =
    ''
    @unauth {
      not header Cookie *mealie.access_token*
      not path /api/* /login /login/* /favicon.ico
    }
    route {
        reverse_proxy :${toString config.site.apps.mealie.port}
    }
    '';
}

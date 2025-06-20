{ config, lib, pkgs, ... }:

let
  mealie-domain = "${config.site.apps.mealie.subdomain}.${config.site.domain}";
  mealie-user = "mealie";
in {
  site.apps.mealie.enabled = true;

  age.secrets.mealie-credentials = {
    owner = mealie-user;
    group = "users";
    file = ../secrets/mealie-credentials-env.age;
  };

  services.mealie = {
    enable = true;
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
      OIDC_AUTO_REDIRECT = "true";
      OIDC_CLIENT_ID = "mealie";
      OIDC_CONFIGURATION_URL = "https://${config.site.apps.authelia.subdomain}.${config.site.domain}/.well-known/openid-configuration";
      OIDC_SIGNUP_ENABLED = "true";
      OIDC_USER_GROUP = config.site.apps.mealie.user-group;
      OIDC_ADMIN_GROUP = config.site.apps.mealie.admin-group;
      DEFAULT_GROUP = "Family";
      DEFAULT_HOUSEHOLD = "Unsorted";
      THEME_LIGHT_PRIMARY = "#239A58";
      THEME_LIGHT_SECONDARY = "#346043";
      THEME_DARK_PRIMARY = "#239A58";
      THEME_DARK_SECONDARY = "#346043";
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

  services.caddy.virtualHosts."${mealie-domain}".extraConfig =
    ''
    handle_path /icons/* {
        root * ${../assets/mealie}
        file_server
    }
    @unauth {
      not header Cookie *mealie.access_token*
      not path /api/* /login /login/* /favicon.ico
    }
    route {
        file_server /favicon.ico {
            root ${../assets/mealie}
        }
        reverse_proxy :${toString config.site.apps.mealie.port}
    }
    '';
}

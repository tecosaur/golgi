{ config, lib, pkgs, ... }:

let
  mealie-domain = "${config.site.apps.mealie.subdomain}.${config.site.domain}";
  mealie-user = "mealie";
  darkenHex = rgb: let
    min = a: b: if a < b then a else b;
    max = a: b: if a > b then a else b;
    clamp = lo: hi: x: max lo (min hi x);
    hexDigits = lib.stringToCharacters "0123456789abcdef";
    toHex = n:
      let
        nn = clamp 0 255 n;
        hi = builtins.floor (nn / 16);
        lo = builtins.floor (nn - hi * 16);
      in
        (builtins.elemAt hexDigits hi) + (builtins.elemAt hexDigits lo);
      r = lib.trivial.fromHexString (builtins.substring 1 2 rgb);
      g = lib.trivial.fromHexString (builtins.substring 3 2 rgb);
      b = lib.trivial.fromHexString (builtins.substring 5 2 rgb);
      mean = (r + g + b) / 3.0;
      mk = orig: orig * 0.5 + mean * 0.2;
      r2 = mk r;
      g2 = mk g;
      b2 = mk b;
  in
    "#${toHex r2}${toHex g2}${toHex b2}";
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
      THEME_LIGHT_PRIMARY = config.site.accent.primary;
      THEME_LIGHT_SECONDARY = darkenHex config.site.accent.primary;
      THEME_DARK_PRIMARY = config.site.accent.primary;
      THEME_DARK_SECONDARY = darkenHex config.site.accent.primary;
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
        root ${config.site.assets}/mealie
        file_server
    }
    @unauth {
      not header Cookie *mealie.access_token*
      not path /api/* /login /login/* /favicon.ico
    }
    route {
        file_server /favicon.ico {
            root ${config.site.assets}/mealie
        }
        reverse_proxy :${toString config.site.apps.mealie.port}
    }
    '';
}

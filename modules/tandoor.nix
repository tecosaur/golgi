{ config, lib, pkgs, ... }:

let
  oidc-config = {
    OAUTH_PKCE_ENABLED = true;
    APPS = [{
      provider_id = "authelia";
      name = "Authelia";
      client_id = "tandoor";
      secret = "##oidc_secret##";
      settings = {
        server_url = "https://${config.site.apps.authelia.subdomain}.${config.site.domain}/.well-known/openid-configuration";
        token_auth_method = "client_secret_basic";
      };
    }];
    SCOPE = [ "openid" "email" "profile" ];
  };
  oidc-secret-file = pkgs.writeText "tandoor-oidc.json" (builtins.toJSON { openid_connect = oidc-config; });
  tandoor-start = pkgs.writeShellScript "tandoor-start" ''
    [ -f "$RUNTIME_DIRECTORY/oidc.json" ] && \
        export SOCIALACCOUNT_PROVIDERS="$(${pkgs.coreutils}/bin/cat "$RUNTIME_DIRECTORY/oidc.json")"
    [ -f "$RUNTIME_DIRECTORY/fdc-api-key" ] && \
        export FDC_API_KEY="$(${pkgs.coreutils}/bin/cat "$RUNTIME_DIRECTORY/fdc-api-key")"
    exec ${config.services.tandoor-recipes.package.python.pkgs.gunicorn}/bin/gunicorn recipes.wsgi \
        --workers 3 --threads 2 --timeout 60 --access-logfile - --error-logfile - --log-level info
  '';
in {
  site.apps.tandoor.enabled = true;

  age.secrets.tandoor-oidc = {
    owner = config.services.tandoor-recipes.user;
    file = ../secrets/oidc/tandoor-secret.age;
  };

  age.secrets.fdc-api-key = {
    owner = config.services.tandoor-recipes.user;
    file = ../secrets/credentials/tandoor-fdc-api-key.age;
  };

  services.tandoor-recipes = {
    enable = true;
    port = config.site.apps.tandoor.port;
    database.createLocally = true;
    extraConfig = {
      ALLOWED_HOSTS = "${config.site.apps.tandoor.subdomain}.${config.site.domain}";
      SOCIAL_PROVIDERS = "allauth.socialaccount.providers.openid_connect";
      ENABLE_SIGNUP = 0;
      HIDE_LOGIN_FORM = 1;
      SOCIALACCOUNT_LOGIN_ON_GET = 1;
      SOCIAL_DEFAULT_ACCESS = 1;
      SOCIAL_DEFAULT_GROUP = "user";
      AI_ALLOWED_URLS = "https://${config.site.apps.llm.subdomain}.${config.site.domain}/v1";
      MEDIA_ROOT = "/var/lib/tandoor-recipes/media";
    };
  };

  systemd.services.tandoor-recipes = {
    preStart = ''
      install -m 0600 '${oidc-secret-file}' "$RUNTIME_DIRECTORY/oidc.json"
      ${lib.getExe pkgs.replace-secret} '##oidc_secret##' \
        '${config.age.secrets.tandoor-oidc.path}' "$RUNTIME_DIRECTORY/oidc.json"
      chmod 0400 "$RUNTIME_DIRECTORY/oidc.json"
      cp '${config.age.secrets.fdc-api-key.path}' "$RUNTIME_DIRECTORY/fdc-api-key"
    '';
    serviceConfig = {
      UMask = lib.mkForce "0027";
      ExecStart = lib.mkForce tandoor-start;
      BindReadOnlyPaths = [ config.age.secrets.tandoor-oidc.path oidc-secret-file ];
    };
  };

  users.users.caddy.extraGroups = [
    config.services.tandoor-recipes.group
  ];

  services.caddy.virtualHosts."${config.site.apps.tandoor.subdomain}.${config.site.domain}".extraConfig = ''
    @tandoor-icon path_regexp icon ^/static/(?:vue3/)?assets/(.*?)[.-][0-9A-Za-z]+(\.png|\.svg)$
    route {
      file_server /favicon.ico {
        root ${config.site.assets}/tandoor
      }
      route @tandoor-icon {
        root ${config.site.assets}/tandoor
        try_files /{re.icon.1}{re.icon.2}
        file_server {
          pass_thru
        }
        reverse_proxy :${toString config.site.apps.tandoor.port}
      }
      handle_path /media/* {
        root ${config.services.tandoor-recipes.extraConfig.MEDIA_ROOT}
        file_server
      }
      reverse_proxy :${toString config.site.apps.tandoor.port}
    }
  '';
}

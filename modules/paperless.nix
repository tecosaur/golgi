{ config, lib, pkgs, ... }:

# *Setup process*
# 1. Comment out `PAPERLESS_DISABLE_REGULAR_LOGIN`
# 2. Log in as `admin`
# 3. Create the groups (`/usersgroups`):
#    a) `users` (basic permissions that everyone should have),
#       at a minimum you probably want this to include:
#       - Document (all)
#       - Tag (all)
#       - Correspondent (all)
#       - Document Type (view)
#       - Saved View (all)
#       - UISettings (all) *important*
#       - History (view)
#       - Note (all)
#       - Share Link (all)
#    b) `admin` (OIDC admin group), with any extra permissions,
#       such as:
#       - Paperless Task
#       - App Config
#       - User
#       - Group
#       - Custom Field
#       - Workflow
# 4. Sign out
# 5. Uncomment `PAPERLESS_DISABLE_REGULAR_LOGIN`

let
  django-allauth-oidc-config = {
    OAUTH_PKCE_ENABLED = true;
    APPS = [
      {
        provider_id = "authelia";
        name = "Single Sign On";
        client_id = "paperless";
        secret = "##oidc_secret##";
        settings = {
          fetch_userinfo = true;
          oauth_pkce_enabled = true;
          server_url = "https://${config.site.apps.authelia.subdomain}.${config.site.domain}/.well-known/openid-configuration";
          token_auth_method = "client_secret_basic";
        };
      }
    ];
    SCOPE = [ "openid" "email" "profile" "groups" ];
  };
  django-allauth-env = pkgs.writeText "paperless-allauth.json"
    "PAPERLESS_SOCIALACCOUNT_PROVIDERS='${builtins.toJSON { openid_connect = django-allauth-oidc-config; }}'\n";
in {
  site.apps.paperless.enabled = true;

  age.secrets.paperless-oidc = {
    owner = "paperless";
    group = "users";
    file = ../secrets/paperless-oidc-secret.age;
  };

  age.secrets.paperless-admin-password = {
    owner = "paperless";
    group = "users";
    file = ../secrets/paperless-admin-password.age;
  };

  services.paperless = {
    enable = true;
    port = config.site.apps.paperless.port;
    dataDir = "/data/paperless";
    configureTika = true;
    passwordFile = config.age.secrets.paperless-admin-password.path;
    settings = {
      PAPERLESS_APP_TITLE = "Paperless";
      PAPERLESS_URL = "https://${config.site.apps.paperless.subdomain}.${config.site.domain}";
      # OIDC
      PAPERLESS_APPS = "allauth.socialaccount.providers.openid_connect";
      PAPERLESS_DISABLE_REGULAR_LOGIN = true;
      PAPERLESS_SOCIAL_AUTO_SIGNUP = true;
      PAPERLESS_ACCOUNT_EMAIL_VERIFICATION = false;
      PAPERLESS_ENABLE_HTTP_REMOTE_USER = true;
      PAPERLESS_SOCIAL_ACCOUNT_DEFAULT_GROUPS = "users"; # Comes with basic permissions
      # PAPERLESS_SOCIAL_ACCOUNT_SYNC_GROUPS = true; # This adds people to `admin`, but removes people from the OIDC non-existent `users` group
      PAPERLESS_REDIRECT_LOGIN_TO_SSO = true;
      PAPERLESS_HTTP_REMOTE_USER_HEADER_NAME = "HTTP_REMOTE_USER";
      PAPERLESS_LOGOUT_REDIRECT_URL = "https://${config.site.apps.paperless.subdomain}.${config.site.domain}";
      # Consumption
      PAPERLESS_CONSUMER_RECURSIVE = true;
      PAPERLESS_CONSUMER_SUBDIRS_AS_TAGS = true;
      # Storage
      PAPERLESS_FILENAME_FORMAT = "{{ owner_username }}/{{ created_year }}/{{ correspondent }}/{{ created_month }}-{{ created_month_name_short }}_{{ title }}";
    };
    environmentFile = "/run/paperless-secrets/oidc-env";
  };

  system.activationScripts.paperless-oidc-env = {
    deps = [ "agenix" ];
    text = ''
      mkdir -p /run/paperless-secrets
      chown -R ${config.services.paperless.user}:users /run/paperless-secrets
      chmod -R 700 /run/paperless-secrets
      cp ${django-allauth-env} /run/paperless-secrets/oidc-env
      ${lib.getExe pkgs.replace-secret} '##oidc_secret##' '${config.age.secrets.paperless-oidc.path}' /run/paperless-secrets/oidc-env
      chmod 400 /run/paperless-secrets/oidc-env
    '';
  };

  systemd.tmpfiles.settings."10-paperless" = {
    "${config.services.paperless.dataDir}".d.mode = "770";
    "${config.services.paperless.mediaDir}".d.mode = "770";
    "${config.services.paperless.consumptionDir}".d.mode = "770";
  };

  systemd.services.paperless-scheduler.serviceConfig.UMask = lib.mkForce "0027";
  systemd.services.paperless-task-queue.serviceConfig.UMask = lib.mkForce "0027";
  systemd.services.paperless-consumer.serviceConfig.UMask = lib.mkForce "0027";
  systemd.services.paperless-web.serviceConfig.UMask = lib.mkForce "0027";
  systemd.services.paperless-exporter.serviceConfig.UMask = lib.mkForce "0027";

  users.users.${config.services.paperless.user}.group = lib.mkForce "users";

  services.caddy.virtualHosts."${config.site.apps.paperless.subdomain}.${config.site.domain}".extraConfig =
    ''
    route {
        file_server /favicon.ico {
            root ${../assets/paperless}
        }
        reverse_proxy :${toString config.site.apps.paperless.port}
    }
    '';
}

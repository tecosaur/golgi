{ config, lib, pkgs, ... }:

let
  warracker-domain = "${config.site.apps.warracker.subdomain}.${config.site.domain}";
  warracker-user = "warracker";
  warracker-dir = config.site.apps.warracker.dir;
  warracker-pkg = pkgs.callPackage ../packages/warracker.nix {  };
  warracker-config = {
    registration_enabled = false;
    email_base_url = "https://${warracker-domain}";
    oidc_enabled = true;
    oidc_only_mode = true;
    oidc_client_id = "warracker";
    oidc_provider_name = "authelia";
    oidc_issuer_url = "https://${config.site.apps.authelia.subdomain}.${config.site.domain}";
    oidc_scope = "openid email profile groups";
    oidc_admin_group = "admin";
  };
in {
  site.apps.warracker.enabled = true;

  age.secrets = {
    warracker-oidc = {
      owner = warracker-user;
      file = ../secrets/warracker-oidc-secret.age;
    };
    warracker-smtp = {
      owner = warracker-user;
      file = ../secrets/fastmail.age;
    };
  };

  systemd.services.warracker = {
    description = "Warracker Flask App";
    after = [ "network-online.target" "postgresql.service" ];
    requires = [ "postgresql.service" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    environment = {
      FLASK_ENV = "production";
      # FLASK_CONFIG = "production";
      LOG_LEVEL = "info";
      BIND_ADDR = "127.0.0.1";
      PORT = toString config.site.apps.warracker.port;
      FRONTEND_URL = "https://${warracker-domain}";
      APP_BASE_URL = "https://${warracker-domain}";
      GUNICORN_WORKERS = "2";
      DB_HOST = "/run/postgresql";
      DB_NAME = warracker-user;
      DB_USER = warracker-user;
      DB_PASSWORD = "";
      UPLOAD_FOLDER = "${warracker-dir}/uploads";
      WARRACKER_FIXED_CONFIG = (pkgs.formats.json {}).generate "warracker.json" warracker-config;
      OIDC_CLIENT_SECRET_FILE = config.age.secrets.warracker-oidc.path;
      SMTP_HOST = config.site.email.server;
      SMTP_PORT = toString config.site.email.port;
      SMTP_USERNAME = config.site.email.username;
      SMTP_PASSWORD_FILE = config.age.secrets.warracker-smtp.path;
      SMTP_FROM_ADDRESS = "Warracker (${config.site.domain}) <services.warracker@${config.site.domain}>";
    };
    serviceConfig = {
      User = warracker-user;
      Group = "users";
      WorkingDirectory = warracker-dir;
      ExecStartPre = "${warracker-pkg}/bin/warracker-migrate";
      ExecStart = "${warracker-pkg}/bin/warracker-gunicorn";
      Restart = "on-failure";
    };
  };

  services.postgresql = {
    enable = true;
    ensureDatabases = [ warracker-user ];
    ensureUsers = [{
      name = warracker-user;
      ensureDBOwnership = true;
    }];
  };

  users.users.${warracker-user} = {
    isSystemUser = true;
    home = warracker-dir;
    createHome = true;
    group = warracker-user;
    extraGroups = [ "users" ];
  };

  users.groups.${warracker-user} = { };

  services.caddy.virtualHosts.${warracker-domain}.extraConfig = ''
    reverse_proxy /api/* :${toString config.site.apps.warracker.port}
    file_server /favicon* {
      root ${../assets/warracker}
    }
    file_server {
      root ${warracker-pkg}/share/warracker/static
      index index.html
    }
  '';
}

{ config, lib, pkgs, ... }:

let
  warracker-domain = "${config.site.apps.warracker.subdomain}.${config.site.domain}";
  warracker-user = "warracker";
  warracker-dir = config.site.apps.warracker.dir;
  warracker-pkg = pkgs.callPackage ../packages/warracker.nix {  };
in {
  site.apps.warracker.enabled = true;

  systemd.services.warracker = {
    description = "Warracker Flask App";
    after = [ "network-online.target" "postgresql.service" ];
    requires = [ "postgresql.service" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    environment = {
      FLASK_ENV = "production";
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
      #--
      OIDC_PROVIDER_NAME = "authelia";
      OIDC_CLIENT_ID = "warracker";
      OIDC_CLIENT_SECRET = "--secret--";
      OIDC_ISSUER_URL = "https://${config.site.apps.authelia.subdomain}.${config.site.domain}";
      OIDC_SCOPE = "openid profile email";
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

  # systemd.tmpfiles.rules = [
  #   "d ${warracker-dir}/uploads 0750 ${cfg.user} ${cfg.group} - -"
  #   "d ${warracker-dir}/cache 0750 ${cfg.user} ${cfg.group} - -"
  # ];

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
    file_server {
      root ${warracker-pkg}/share/warracker/static
      index index.html
    }
  '';
}

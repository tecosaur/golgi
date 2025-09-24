{ config, lib, pkgs, ... }:

let
  vikunja-domain = "${config.site.apps.vikunja.subdomain}.${config.site.domain}";
  vikunja-user = "vikunja";
  custom-public-dir = ../assets/vikunja/public;
in {
  site.apps.vikunja.enabled = true;

  age.secrets.vikunja-oidc = {
    owner = vikunja-user;
    group = vikunja-user;
    file = ../secrets/vikunja-oidc.age;
  };

  age.secrets.vikunja-fastmail = {
    owner = vikunja-user;
    group = vikunja-user;
    file = ../secrets/fastmail.age;
  };

  services.vikunja = {
    enable = true;
    package = pkgs.callPackage ../packages/vikunja.nix { };
    frontendScheme = "https";
    frontendHostname = vikunja-domain;
    port = config.site.apps.vikunja.port;
    database = {
      type = "postgres";
      user = vikunja-user;
      host = "/run/postgresql";
    };
    settings = {
      auth = {
        local.enabled = false;
        openid = {
          enabled = true;
          redirecturl = "https://${vikunja-domain}/auth/openid/";
          providers = {
            authelia = {
              name = "Authelia";
              authurl = "https://${config.site.apps.authelia.subdomain}.${config.site.domain}";
              clientid = "vikunja";
              clientsecret.file = config.age.secrets.vikunja-oidc.path;
            };
          };
        };
      };
      service = {
        enableuserdeletion = false;
      };
      mailer = {
        enabled = true;
        host = config.site.email.server;
        post = config.site.email.port;
        username = config.site.email.username;
        password.file = config.age.secrets.vikunja-fastmail.path;
        fromemail = "services.tasks@${config.site.domain}";
      };
      defaultsettings = {
        discoverable_by_name = true;
        week_start = 1;
      };
    };
  };

  services.postgresql = {
    enable = true;
    ensureDatabases = [ config.services.vikunja.database.user ];
    ensureUsers = [
      { name = config.services.vikunja.database.user;
        ensureDBOwnership = true;
      }
    ];
  };

  users.users.${vikunja-user} = {
    group = vikunja-user;
    isSystemUser = true;
  };
  users.groups.${vikunja-user} = {};

  services.caddy.virtualHosts."${vikunja-domain}".extraConfig =
    ''
    @public-assets path /favicon.ico /images/icons/*
    route {
        file_server @public-assets {
            root ${custom-public-dir}
        }
        reverse_proxy :${toString config.site.apps.vikunja.port}
    }
    '';
}

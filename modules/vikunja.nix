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
        host = "smtp.fastmail.com";
        post = 587;
        username = "tec@${config.site.domain}";
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

  services.authelia.instances.main.settings = {
    identity_providers.oidc = {
      authorization_policies.vikunja = {
        default_policy = "one_factor";
        rules = [
          {
            policy = "two_factor";
            subject = [ [ "group:${config.site.apps.vikunja.user-group}"
                          "group:${config.site.apps.vikunja.admin-group}" ] ];
          }
        ];
      };
      clients = [
        {
          client_id = "vikunja";
          client_name = "Vikunja";
          client_secret = "$argon2id$v=19$m=65536,t=3,p=4$zRMdh029w57vBVKYJUbrOA$XpthqZlqEa6neEoIffR8wHEt++KuMykATd/tte//4II";
          authorization_policy = "vikunja";
          public = false;
          consent_mode = "implicit";
          redirect_uris = [ "https://${vikunja-domain}/auth/openid/authelia" ];
          scopes = [ "openid" "email" "profile" ];
          userinfo_signed_response_alg = "none";
          token_endpoint_auth_method = "client_secret_basic";
        }
      ];
    };
  };

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

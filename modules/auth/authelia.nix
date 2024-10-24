{ config, lib, ... }:

let
  auth-domain = "auth.${config.globals.domain}";
  authelia-user = "authelia";
  authelia-port = 9091;
in {
  age.secrets = {
    authelia-session = {
      owner = authelia-user;
      group = "users";
      file = ../../secrets/authelia-session.age;
    };
    authelia-storage = {
      owner = authelia-user;
      group = "users";
      file = ../../secrets/authelia-storage.age;
    };
    authelia-jwt = {
      owner = authelia-user;
      group = "users";
      file = ../../secrets/authelia-jwt.age;
    };
    authelia-smtp = {
      owner = authelia-user;
      group = "users";
      file = ../../secrets/fastmail.age;
    };
    postgres-authelia = {
      owner = authelia-user;
      group = "users";
      file = ../../secrets/postgres-authelia.age;
    };
    authelia-oidc-hmac = {
      owner = authelia-user;
      group = "users";
      file = ../../secrets/authelia-oidc-hmac.age;
    };
    authelia-oidc-issuer-key = {
      owner = authelia-user;
      group = "users";
      file = ../../secrets/authelia-oidc-issuer.pem.age;
    };
    authelia-lldap-admin-password = {
      owner = authelia-user;
      group = "users";
      file = ../../secrets/lldap-admin-password.age;
    };
  };

  services.authelia.instances.main = {
    enable = true;
    user = authelia-user;
    group = authelia-user;
    secrets =  {
      jwtSecretFile = config.age.secrets.authelia-jwt.path;
      oidcHmacSecretFile = config.age.secrets.authelia-oidc-hmac.path;
      oidcIssuerPrivateKeyFile = config.age.secrets.authelia-oidc-issuer-key.path;
      sessionSecretFile = config.age.secrets.authelia-session.path;
      storageEncryptionKeyFile = config.age.secrets.authelia-storage.path;
    };
    settings = {
      theme = "auto";
      authentication_backend.ldap = {
        address = "ldap://localhost:${toString config.services.lldap.settings.ldap_port}";
        base_dn = config.services.lldap.settings.ldap_base_dn;
        users_filter = "(&({username_attribute}={input})(objectClass=person))";
        groups_filter = "(member={dn})";
        user = "uid=${config.services.lldap.settings.ldap_user_dn},ou=people,${config.services.lldap.settings.ldap_base_dn}";
      };
      server.address = "tcp://:${toString authelia-port}";
      session = {
        cookies = [
          {
            domain = config.globals.domain;
            authelia_url = "https://${auth-domain}";
          }
        ];
      };
      access_control = {
        default_policy = "deny";
        rules = lib.mkAfter [
          {
            domain = "*.${config.globals.domain}";
            policy = "one_factor";
          }
        ];
      };
      storage.postgres = {
        address = "unix:///run/postgresql";
        database = authelia-user;
        username = authelia-user;
      };
      notifier.smtp = {
        address = "smtp.fastmail.com:587";
        username = "tec@tecosaur.net";
        sender = "Authelia <auth@tecosaur.net>";
      };
      log.level = "info";
      identity_providers.oidc = {
        cors = {
          endpoints = [ "token" ];
          allowed_origins_from_client_redirect_uris = true;
        };
        authorization_policies.default = {
          default_policy = "one_factor";
          rules = [
            {
              policy = "deny";
              subject = "group:lldap_strict_readonly";
            }
          ];
        };
      };
      # Necessary for Caddy integration
      # See https://www.authelia.com/integration/proxies/caddy/#implementation
      server.endpoints.authz.forward-auth.implementation = "ForwardAuth";
    };
    environmentVariables = {
      AUTHELIA_STORAGE_POSTGRES_PASSWORD_FILE = config.age.secrets.postgres-authelia.path;
      AUTHELIA_AUTHENTICATION_BACKEND_LDAP_PASSWORD_FILE = config.age.secrets.authelia-lldap-admin-password.path;
      AUTHELIA_NOTIFIER_SMTP_PASSWORD_FILE = config.age.secrets.authelia-smtp.path;
    };
  };

  services.postgresql = {
    enable = true;
    ensureDatabases = [ authelia-user ];
    ensureUsers = [
      { name = authelia-user;
        ensureDBOwnership = true;
      }
    ];
  };

  systemd.services."authelia-main" = let
    dependencies = [
      "postgresql.service"
      "lldap.service"
    ];
  in {
    after = dependencies;
    requires = dependencies;
  };

  users.users.${authelia-user} = {
    group = authelia-user;
    isSystemUser = true;
  };
  users.groups.${authelia-user} = {};

  services.caddy = {
    virtualHosts."${auth-domain}".extraConfig = ''reverse_proxy localhost:${toString authelia-port}'';
    # A Caddy snippet that can be imported to enable Authelia in front of a service
    # Taken from https://www.authelia.com/integration/proxies/caddy/#subdomain
    extraConfig = ''
        (auth) {
            forward_auth localhost:${toString authelia-port} {
                uri /api/authz/forward-auth
                copy_headers Remote-User Remote-Groups Remote-Email Remote-Name
            }
        }
    '';
  };
}

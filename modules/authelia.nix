{ config, lib, ... }:

let
  auth-domain = "auth.${config.globals.domain}";
  authelia-user = "authelia";
  authelia-port = 9091;
in {
  age.secrets = {
    authelia-storage = {
      owner = authelia-user;
      group = "users";
      file = ../secrets/authelia-storage.age;
    };
    authelia-jwt = {
      owner = authelia-user;
      group = "users";
      file = ../secrets/authelia-jwt.age;
    };
    authelia-smtp = {
      owner = authelia-user;
      group = "users";
      file = ../secrets/fastmail.age;
    };
    postgres-authelia = {
      owner = authelia-user;
      group = "users";
      file = ../secrets/postgres-authelia.age;
    };
  };

  services.authelia.instances.main = {
    enable = true;
    user = authelia-user;
    group = authelia-user;
    secrets =  {
      storageEncryptionKeyFile = config.age.secrets.authelia-storage.path;
      jwtSecretFile = config.age.secrets.authelia-jwt.path;
    };
    settings = {
      theme = "auto";
      authentication_backend.file.path = "/etc/authelia/users_database.yml";
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
      # Necessary for Caddy integration
      # See https://www.authelia.com/integration/proxies/caddy/#implementation
      server.endpoints.authz.forward-auth.implementation = "ForwardAuth";
    };
    environmentVariables = {
      AUTHELIA_STORAGE_POSTGRES_PASSWORD_FILE = config.age.secrets.postgres-authelia.path;
      AUTHELIA_NOTIFIER_SMTP_PASSWORD_FILE = config.age.secrets.authelia-smtp.path;
    };
  };

  environment.etc."authelia/users_database.yml" = {
    mode = "0400";
    user = authelia-user;
    text = ''
      users:
        tec:
          disabled: false
          displayname: tec
          # password of password
          password: $argon2id$v=19$m=65536,t=3,p=4$2ohUAfh9yetl+utr4tLcCQ$AsXx0VlwjvNnCsa70u4HKZvFkC8Gwajr2pHGKcND/xs
          email: tec@tecosaur.net
          groups:
            - admin
            - dev
    '';
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

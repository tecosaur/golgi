{ config, lib, ... }:

let
  lldap-user = "lldap";
  lldap-web-domain = "users.${config.globals.domain}";
in {
  age.secrets = {
    lldap-jwt = {
      owner = lldap-user;
      group = "users";
      file = ../../secrets/lldap-jwt.age;
    };
    lldap-key-seed = {
      owner = lldap-user;
      group = "users";
      file = ../../secrets/lldap-key-seed.age;
    };
    lldap-admin-password = {
      owner = lldap-user;
      group = "users";
      file = ../../secrets/lldap-admin-password.age;
    };
  };

  services.lldap = {
    enable = true;
    settings = {
      ldap_base_dn = "dc=tecosaur,dc=net";
      ldap_user_dn = "admin";
      ldap_user_email = "lldap-admin@tecosaur.net";
      database_url = "postgresql://${lldap-user}@localhost/${lldap-user}?host=/run/postgresql";
    };
    environment = {
      LLDAP_JWT_SECRET_FILE = config.age.secrets.lldap-jwt.path;
      LLDAP_KEY_SEED_FILE = config.age.secrets.lldap-key-seed.path;
      LLDAP_LDAP_USER_PASS_FILE = config.age.secrets.lldap-admin-password.path;
    };
  };

  services.postgresql = {
    enable = true;
    ensureDatabases = [ lldap-user ];
    ensureUsers = [
      { name = lldap-user;
        ensureDBOwnership = true;
      }
    ];
  };

  systemd.services.lldap = let
    dependencies = [
      "postgresql.service"
    ];
  in {
    after = dependencies;
    requires = dependencies;
  };

  users.users.${lldap-user} = {
    group = lldap-user;
    isSystemUser = true;
  };
  users.groups.${lldap-user} = {};

  services.caddy.virtualHosts.${lldap-web-domain}.extraConfig = ''
    reverse_proxy localhost:${toString config.services.lldap.settings.http_port}
  '';
}

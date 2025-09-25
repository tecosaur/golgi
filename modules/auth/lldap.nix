{ config, lib, ... }:

let
  lldap-user = "lldap";
  lldap-web-domain = "${config.site.apps.lldap.subdomain}.${config.site.domain}";
  lldap-base-dn = lib.strings.concatMapStringsSep "," (dc: "dc=" + dc) (lib.splitString "." config.site.domain);
in {
  site.apps.lldap.enabled = true;

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
      ldap_base_dn = lldap-base-dn;
      ldap_user_dn = "admin";
      ldap_user_email = "lldap-admin@${config.site.domain}";
      ldap_user_pass_file = config.age.secrets.lldap-admin-password.path;
      jwt_secret_file = config.age.secrets.lldap-jwt.path;
      force_ldap_user_pass_reset = "always";
      database_url = "postgresql://${lldap-user}@localhost/${lldap-user}?host=/run/postgresql";
    };
    environment = {
      LLDAP_KEY_SEED_FILE = config.age.secrets.lldap-key-seed.path;
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

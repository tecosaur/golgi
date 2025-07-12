{ config, lib, pkgs, ... }:

let
  auth-domain = "${config.site.apps.authelia.subdomain}.${config.site.domain}";
  authelia-port = config.site.apps.authelia.port;
  authelia-user = "authelia";
  assets-no-symlinks = pkgs.runCommand "autheleia-assets" {} ''
    mkdir -p $out
    cp -rL ${../../assets}/authelia/* $out
  '';
in {
  site.apps.authelia.enabled = true;

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
      server = {
        address = "tcp://:${toString authelia-port}";
        asset_path = assets-no-symlinks;
      };
      session = {
        cookies = [
          ({
            domain = config.site.domain;
            authelia_url = "https://${auth-domain}";
          } // lib.optionalAttrs config.site.apps.homepage.enabled {
            default_redirection_url = "https://${config.site.apps.homepage.subdomain}.${config.site.domain}";
          })
        ];
        redis.host = "/run/redis-authelia-main/redis.sock";
      };
      access_control = {
        default_policy = "deny";
        rules = lib.mkAfter [
          {
            domain = "*.${config.site.domain}";
            policy = "one_factor";
          }
        ];
      };
      password_policy.standard = {
        enabled = true;
        min_length = 12;
      };
      webauthn = {
        enable_passkey_login = true;
        experimental_enable_passkey_uv_two_factors = true;
        selection_criteria = {
          attachment = "platform";
          user_verification = "preferred";
        };
        attestation_conveyance_preference = "direct";
        filtering.prohibit_backup_eligibility = false;
        metadata = {
          enabled = true;
          validate_trust_anchor = true;
          validate_entry = false;
          validate_status = true;
          validate_entry_permit_zero_aaguid = false;
        };
      };
      authentication_backend.ldap = {
        address = "ldap://localhost:${toString config.services.lldap.settings.ldap_port}";
        base_dn = config.services.lldap.settings.ldap_base_dn;
        users_filter = "(&({username_attribute}={input})(objectClass=person))";
        groups_filter = "(member={dn})";
        user = "uid=${config.services.lldap.settings.ldap_user_dn},ou=people,${config.services.lldap.settings.ldap_base_dn}";
      };
      storage.postgres = {
        address = "unix:///run/postgresql";
        database = authelia-user;
        username = authelia-user;
      };
      notifier.smtp = {
        address = "smtp.fastmail.com:587";
        username = "tec@tecosaur.net";
        sender = "${config.site.domain} — Authentication <services.authentication@${config.site.domain}>";
        subject = "{title}";
      };
      log.level = "debug";
      identity_providers.oidc = {
        cors = {
          endpoints = [ "authorization" "token" "revocation" "introspection" "userinfo" ];
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

  services.redis.servers.authelia-main = {
    enable = true;
    user = authelia-user;
    port = 0;
    unixSocket = "/run/redis-authelia-main/redis.sock";
    unixSocketPerm = 600;
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

  services.caddy.virtualHosts."${auth-domain}".extraConfig =
    ''reverse_proxy localhost:${toString authelia-port}'';
}

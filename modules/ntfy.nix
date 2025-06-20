{ config, lib, pkgs, ... }:

let
  ntfy-domain = "${config.site.apps.ntfy.subdomain}.${config.site.domain}";
  ntfy-user = "ntfy";
in {
  site.apps.ntfy.enabled = true;

  age.secrets.webpush-keys-env = {
    owner = ntfy-user;
    group = "users";
    file = ../secrets/ntfy-webpush-keys-env.age;
  };

  services.ntfy-sh = {
    enable = true;
    user = ntfy-user;
    group = ntfy-user;
    settings = {
      base-url = "https://${ntfy-domain}";
      listen-http = ":${toString config.site.apps.ntfy.port}";
      upstream-base-url = "https://ntfy.sh";
      behind-proxy = true;
      web-root = "/app";
      web-push-file = "${config.site.apps.ntfy.dir}/webpush.db";
      web-push-email-address = "services.ntfy@${config.site.domain}";
      auth-file = "${config.site.apps.ntfy.dir}/users.db";
      auth-default-access = "read-only";
      attachment-cache-dir = "${config.site.apps.ntfy.dir}/attachments";
      cache-file = "${config.site.apps.ntfy.dir}/cache.db";
    };
  };

  users.users."${ntfy-user}" = {
    isSystemUser = true;
    group = ntfy-user;
  };

  users.groups."${ntfy-user}" = {};

  systemd.services.ntfy-sh = {
    serviceConfig = {
      EnvironmentFile = config.age.secrets.webpush-keys-env.path;
      StateDirectory = lib.mkForce "${baseNameOf config.site.apps.ntfy.dir}";
    };
  };

  services.caddy.virtualHosts."${ntfy-domain}".extraConfig =
    ''
    route /app {
        import auth
        reverse_proxy localhost:${toString config.site.apps.ntfy.port}
    }
    route * {
        reverse_proxy :${toString config.site.apps.ntfy.port}
    }
    '';
}

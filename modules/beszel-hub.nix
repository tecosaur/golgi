{ config, lib, pkgs, ... }:

let
  beszel-domain = "${config.site.apps.beszel.subdomain}.${config.site.domain}";
in {
  site.apps.beszel.enabled = true;

  services.beszel.hub = {
    enable = true;
    port = config.site.apps.beszel.port;
    environment = {
      APP_URL = "https://${beszel-domain}";
      SHARE_ALL_SYSTEMS = "true";
      USER_CREATION = "true";
      USER_EMAIL = "admin@${config.site.domain}";
      USER_PASSWORD = "letmeinn";
      DISABLE_PASSWORD_AUTH = "true"; # Uncomment after setting up web UI
    };
  };

  services.caddy.virtualHosts."${beszel-domain}".extraConfig =
    ''
    handle /static/icon.svg {
        uri strip_prefix /static/
        root ${config.site.assets}/beszel
        file_server
    }
    reverse_proxy :${toString config.site.apps.beszel.port}
    '';
}

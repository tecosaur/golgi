{ config, lib, pkgs, ... }:

{
  site.apps.dawarich.enabled = true;

  age.secrets.dawarich-oidc = {
    owner = "dawarich";
    file = ../secrets/oidc/dawarich-secret.age;
  };

  services.dawarich = {
    enable = true;
    localDomain = "${config.site.apps.dawarich.subdomain}.${config.site.domain}";
    webPort = config.site.apps.dawarich.port;
    configureNginx = false;
    environment = {
      OIDC_CLIENT_ID = "dawarich";
      # OIDC_CLIENT_SECRET is set in the age secret file
      OIDC_ISSUER = "https://${config.site.apps.authelia.subdomain}.${config.site.domain}";
      OIDC_REDIRECT_URI = "https://${config.site.apps.dawarich.subdomain}.${config.site.domain}/users/auth/openid_connect/callback";
      OIDC_PKCE_ENABLED = "true";
      OIDC_PROVIDER_NAME = "Authelia";
      OIDC_AUTO_REGISTER = "true";
      ALLOW_EMAIL_PASSWORD_REGISTRATION = "false";
      ALLOW_EMAIL_PASSWORD_LOGIN = "false";
      PHOTON_API_HOST = "photon.koalasec.org";
      PHOTON_API_USE_HTTPS = "true";
      STORE_GEODATA = "true";
    };
    extraEnvFiles = [ config.age.secrets.dawarich-oidc.path ];
  };

  services.caddy.virtualHosts."${config.site.apps.dawarich.subdomain}.${config.site.domain}".extraConfig =
    ''
    reverse_proxy :${toString config.site.apps.dawarich.port}
    '';
}

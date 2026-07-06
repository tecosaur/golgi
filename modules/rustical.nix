{ config, lib, pkgs, ... }:

let
  rustical-domain = "${config.site.apps.rustical.subdomain}.${config.site.domain}";
in {
  site.apps.rustical.enabled = true;

  age.secrets.rustical-oidc = {
    file = ../secrets/rustical-oidc-secret-env.age;
  };
  
  services.rustical = {
    enable = true;
    settings = {
      dav_push.enabled = true;
      frontend = {
        enabled = true;
        allow_password_login = false;
      };
      http = {
        bind = "[::]:${toString config.site.apps.rustical.port}";
      };
      oidc = {
        name = "Authelia";
        issuer = "https://${config.site.apps.authelia.subdomain}.${config.site.domain}";
        client_id = "rustical";
        claim_userid = "preferred_username";
        scopes = [ "openid" "profile" "email" "groups" ];
        # assign_memberships = {
        #   family = [ "group.family" ];
        # };
        allow_sign_up = true;
      };
    };
    environmentFiles = [ config.age.secrets.rustical-oidc.path ];
  };

  services.caddy.virtualHosts."${rustical-domain}".extraConfig =
    ''
    reverse_proxy :${toString config.site.apps.rustical.port}
    '';
}

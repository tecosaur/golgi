{ config, lib, pkgs, ... }:

let
  rustical-domain = "${config.site.apps.rustical.subdomain}.${config.site.domain}";
  rustical-start = pkgs.writeShellScript "rustical-start" ''
    export RUSTICAL_OIDC__CLIENT_SECRET="$(< "$CREDENTIALS_DIRECTORY/oidc-secret")"
    exec ${lib.getExe config.services.rustical.package}
  '';
in {
  site.apps.rustical.enabled = true;

  age.secrets.rustical-oidc = {
    file = ../secrets/rustical-oidc-secret.age;
  };

  systemd.services.rustical.serviceConfig = {
    LoadCredential = [ "oidc-secret:${config.age.secrets.rustical-oidc.path}" ];
    ExecStart = lib.mkForce rustical-start;
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
  };

  services.caddy.virtualHosts."${rustical-domain}".extraConfig =
    ''
    reverse_proxy :${toString config.site.apps.rustical.port}
    '';
}

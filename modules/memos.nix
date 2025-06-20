{ config, lib, pkgs, ... }:

let
  memos-pkg = pkgs.memos;
  memos-domain = "${config.site.apps.memos.subdomain}.${config.site.domain}";
  memos-port = toString config.site.apps.memos.port;
in {
  site.apps.memos.enabled = true;

  systemd.services.memos = {
    description = "memos";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    serviceConfig = {
      Type = "simple";
      ExecStart = "${memos-pkg}/bin/memos --mode prod --data /var/lib/memos --port ${memos-port}";
      Restart = "always";
      RestartSec = 5;
      User = "memos";
      Group = "memos";
      StateDirectory = "memos";
      StandardOutput = "journal";
    };
  };

  users.users.memos = {
    isSystemUser = true;
    group = "memos";
  };

  users.groups.memos = { };

  # See <https://github.com/usememos/memos/issues/4318> for why
  # the `redir` directive is used here.
  services.caddy.virtualHosts."${memos-domain}".extraConfig =
    ''
    @doauth {
        path /
        header Cookie *authelia_session*
        not header Cookie *memos.access-token*
    }
    @custom-assets {
        path /logo.webp
        path /full-logo.webp
    }
    redir @doauth https://${config.site.apps.authelia.subdomain}.${config.site.domain}/api/oidc/authorization?client_id=memos&redirect_uri=https://${memos-domain}/auth/callback&state=auth.signin.SSO%20(Authelia)-1&response_type=code&scope=openid%20profile%20email
    handle @custom-assets {
        root * ${../assets/memos}
        file_server
    }
    reverse_proxy :${memos-port}
    '';
}

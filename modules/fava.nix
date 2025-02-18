{ config, lib, pkgs, ... }:

let
  fava-domain = "${config.site.apps.fava.subdomain}.${config.site.domain}";
  fava-port = toString config.site.apps.fava.port;
  fava-user = "tec";
  bean-file = "${config.services.syncthing.dataDir}/tec-ledger/finance.beancount";
in {
  site.apps.fava.enabled = true;

  systemd.services.fava = {
    description = "Fava web interface for Beancount";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    serviceConfig = {
      Type = "simple";
      ExecStart = "${pkgs.fava}/bin/fava -H 127.0.0.1 -p ${fava-port} ${bean-file}";
      Restart = "always";
      User = "fava";
      Group = "fava";
      StateDirectory = "fava";
      StandardOutput = "journal";
    };
  };

  users.users.fava = {
    isSystemUser = true;
    group = "fava";
    extraGroups = [ config.services.syncthing.user ];
  };

  users.groups.fava = { };

  services.authelia.instances.main.settings.access_control.rules = [
    {
      domain = fava-domain;
      policy = "two_factor";
      subject = [ "user:${fava-user}" ];
    }
    {
      domain = fava-domain;
      policy = "deny";
    }
  ];

  services.caddy.virtualHosts."${fava-domain}".extraConfig = ''
    import auth
    reverse_proxy :${fava-port}
  '';
}

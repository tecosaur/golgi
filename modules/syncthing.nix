{ config, lib, ... }:

with lib;

let
  domain = config.site.domain;
  syncthing-domain = "${config.site.apps.syncthing.subdomain}.${config.site.domain}";
  public-domain = "public.${domain}";
  my-computers = [ "tranquillity" "demure" "ict1634" ];
in {
  site.apps.syncthing.enabled = true;

  services.syncthing = {
    enable = true;
    dataDir = config.site.apps.syncthing.dir;
    guiAddress = "localhost:8384";
    overrideDevices = true;
    overrideFolders = true;
    settings = {
      gui = {
        authMode = "ldap";
      };
      ldap = {
        address = "localhost:${toString config.services.lldap.settings.ldap_port}";
        bindDN = "uid=%s,ou=people,${config.services.lldap.settings.ldap_base_dn}";
        transport = "nontls";
        searchBaseDN = "ou=people,${config.services.lldap.settings.ldap_base_dn}";
        searchFilter = "(|(memberof=cn=${config.site.apps.syncthing.user-group},ou=groups,${config.services.lldap.settings.ldap_base_dn})(memberof=cn=${config.site.apps.syncthing.admin-group},ou=groups,${config.services.lldap.settings.ldap_base_dn}))";
      };
      devices = {
        "tranquillity" = { id = "VXWXMXK-MWENVPV-PV75JQH-45OP44F-QMPH645-JVWGJB2-C2GKHSV-QARV5A2"; };
        "demure"       = { id = "DLCN7FP-BMHTAG6-QZHYGPJ-74IALUD-NZII77W-K73SPGU-L7QNGIS-NO674AH"; };
        "phone"        = { id = "IMNPYY2-BZMILMV-PYUCUOS-UCO4WNJ-UBRW7EY-VESRBGA-XHTNZ6G-E34J5QC"; };
        "ict1634"      = { id = "EG33JRV-Y6DUTXW-CNLYOLZ-H5A6SLS-I6INZIS-VISOZK3-2JV62MV-24K45A7"; };
      };
      folders = {
        "Public" = {
          id = "tec-public";
          path = "~/public";
          devices = [ "tranquillity" "demure" "phone" ];
          type = "receiveonly";
        };
        "Zotero Storage" = {
          id = "tec-zotero-storage";
          path = "~/tec-zotero-storage";
          devices = my-computers;
          type = "receiveonly";
        };
        "Fonts" = {
          id = "tec-fonts";
          path = "~/tec-fonts";
          devices = my-computers;
          type = "receiveonly";
        };
      };
    };
  };

  users.users = (mkIf config.services.caddy.enable {
    syncthing = {
        homeMode = "750";
    };
    caddy.extraGroups = [ config.services.syncthing.group ];
  });

  services.caddy.virtualHosts."${syncthing-domain}".extraConfig =
    ''
    reverse_proxy ${config.services.syncthing.guiAddress} {
        header_up Host {upstream_hostport}
    }
    '';
  services.caddy.virtualHosts."${public-domain}".extraConfig =
    ''
    root * ${config.services.syncthing.dataDir}/public/.build
    file_server
    '';
}

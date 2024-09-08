{ config, lib, ... }:

with lib;

let
  domain = config.globals.domain;
  syncthing-domain = "syncthing.${domain}";
  public-domain = "public.${domain}";
in {
  services.syncthing = {
    enable = true;
    dataDir = "/var/lib/syncthing";
    guiAddress = "localhost:8384";
    overrideDevices = true;
    overrideFolders = true;
    settings = {
      gui = {
        user = "tec";
        password = "$2a$10$yXPBFhobbJGT3FRNEWmdRO891ZLTF247XQ2fYmJK8dsqzIWLKOPKC";
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
          devices = [ "tranquillity" "demure" "ict1634" ];
          type = "receiveonly";
        };
      };
    };
  };

  users.users = (mkIf config.services.caddy.enable {
    syncthing = {
        homeMode = "750";
    };
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

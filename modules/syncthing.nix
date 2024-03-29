{ config, lib, ... }:

with lib;

{
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
      };
      folders = {
        "tec-public" = {
          path = "~/public";
          devices = [ "tranquillity" "demure" "phone" ];
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
}

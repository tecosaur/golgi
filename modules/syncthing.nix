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
        "phone"        = { id = "IMNPYY2-BZMILMV-PYUCUOS-UCO4WNJ-UBRW7EY-VESRBGA-XHTNZ6G-E34J5QC"; };
      };
      folders = {
        "tec-public" = {
          path = "~/public";
          devices = [ "tranquillity" "phone" ];
          type = "receiveonly";
        };
      };
    };
  };

  users.users = (mkIf config.services.caddy.enable {
    caddy = {
      extraGroups = [ "syncthing" ];
    };
    syncthing = {
        homeMode = "750";
    };
  });
}

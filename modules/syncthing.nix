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
      };
    };
  };
}

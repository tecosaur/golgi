{ config, lib, pkgs, ... }:

let
  lyrion-domains = [ "music.lan" "local.music" ];
  music-dir = "/data/media/music";
  lyrion-web-port = 9000;
in {
  services.slimserver = {
    enable = true;
  };

  systemd.services.slimserver.serviceConfig = {
    NoNewPrivileges = true;
    LockPersonality = true;
    ProtectSystem = "strict";
    ProtectHome = true;
    PrivateTmp = true;
    PrivateUsers = true;
    PrivateDevices = true;
    ProtectKernelTunables = true;
    ProtectKernelModules = true;
    ProtectKernelLogs = true;
    ProtectControlGroups = true;
    ProtectHostname = true;
    ProtectClock = true;
    ProtectProc = "invisible";
    ProcSubset = "pid";
    RemoveIPC = true;
    RestrictRealtime = true;
    RestrictNamespaces = true;
    RestrictSUIDSGID = true;
    MemoryDenyWriteExecute = true;
    StateDirectory = "slimserver";
    ReadOnlyPaths = [ music-dir "/nix" ];
    ReadWritePaths = [ "/var/lib/slimserver" pkgs.slimserver ];
    UMask = "0077";
    DevicePolicy = "closed";
    SystemCallArchitectures = "native";
    SystemCallFilter = [
      " " # This is needed to clear the SystemCallFilter existing definitions
      "~@reboot"
      "~@swap"
      "~@obsolete"
      "~@mount"
      "~@module"
      "~@debug"
      "~@cpu-emulation"
      "~@clock"
      "~@raw-io"
      "~@privileged"
    ];
    CapabilityBoundingSet = [ " " "CAP_NET_BROADCAST" ];
  };

  networking.firewall.allowedTCPPorts = [ 3483 9000 9090 ];
  networking.firewall.allowedUDPPorts = [ 3483 ];

  services.caddy.virtualHosts = lib.mkMerge (map (domain: {
    "${domain}".extraConfig =
      ''
      handle /html/images/icon* {
          uri strip_prefix /html/images/
          root ${config.site.assets}/lyrion
          file_server
      }
      reverse_proxy :${toString lyrion-web-port}
      tls internal
      '';
    "http://${domain}".extraConfig =
      ''
      handle /html/images/icon* {
          uri strip_prefix /html/images/
          root ${config.site.assets}/lyrion
          file_server
      }
      reverse_proxy :${toString lyrion-web-port}
      '';
  }) lyrion-domains);
}

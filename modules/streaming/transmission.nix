{ config, lib, pkgs, ... }:

let
  download-dir = "/data/media/downloads";
  incomplete-dir = "${download-dir}/.incomplete";
  extra-dirs = [ "/data/media" ];
in {
  site.apps.transmission.enabled = true;

  services.transmission = {
    enable = true;
    group = "users";
    package = pkgs.transmission_4;
    openRPCPort = true; # Make accessible over the LAN (but not WAN)
    webHome = pkgs.flood-for-transmission;
    settings = {
      rpc-bind-address = "0.0.0.0";
      rpc-port = config.site.apps.transmission.port;
      rpc-whitelist = "127.0.0.1,192.168.1.*,100.*.*.*"; # Self, LAN, Tailnet
      rpc-host-whitelist = "192.168.1.*,${config.site.apps.transmission.subdomain}.${config.site.domain},100.*.*.*,nas.lan,${config.site.server.host}.${config.site.apps.headscale.magicdns-subdomain}.${config.site.domain}";
      rpc-authentication-required = false;
      download-dir = download-dir;
      incomplete-dir = incomplete-dir;
      rename-partial-files = true;
      umask = "002";
    };
  };

  systemd.services.transmission.serviceConfig = {
    UMask = lib.mkForce "0007";
    BindPaths = extra-dirs;
  };

  systemd.tmpfiles.rules = [
    "d ${download-dir} 0775 ${config.services.transmission.user} users - -"
    "d ${incomplete-dir} 0775 ${config.services.transmission.user} users - -"
  ];
}

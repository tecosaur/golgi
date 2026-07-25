{ config, lib, pkgs, ... }:

let
  relay-port = config.site.apps.headscale.relay-port;
  tags = lib.optional (relay-port != null) "sys-relay";
in {
  age.secrets.tailscale-preauth = {
    owner = "root";
    group = "root";
    file = ../secrets/tailscale-preauth.age;
  };

  services.tailscale = {
    enable = true;
    openFirewall = true;
    useRoutingFeatures = "server";
    # key generated with: `headscale preauthkeys create -u 1 -e 99y --reusable --tags tag:sys-relay`
    authKeyFile = lib.mkIf config.site.apps.headscale.enabled config.age.secrets.tailscale-preauth.path;
    extraUpFlags = [
      "--reset"
      "--accept-dns=false" # No need for MagicDNS
      "--advertise-exit-node"
      # "--ssh"
    ] ++ lib.optional config.site.apps.headscale.enabled
      "--login-server=https://${config.site.apps.headscale.subdomain}.${config.site.domain}";
    extraSetFlags = lib.optional (relay-port != null)
      "--relay-server-port=${toString relay-port}";
  };

  networking.firewall.allowedTCPPorts = lib.optional (relay-port != null) relay-port;
  networking.firewall.allowedUDPPorts = lib.optional (relay-port != null) relay-port;

  services.networkd-dispatcher = {
    enable = true;
    rules."50-tailscale" = {
      onState = ["routable"];
      script = "${lib.getExe pkgs.ethtool} -K enp1s0 rx-udp-gro-forwarding on rx-gro-list off";
    };
  };
}

{ config, lib, pkgs, ... }:

{
  age.secrets.tailscale-preauth = {
    owner = "root";
    group = "root";
    file = ../secrets/tailscale-preauth.age;
  };

  services.tailscale = {
    enable = true;
    openFirewall = true;
    useRoutingFeatures = "server";
    # key generated with: `headscale preauthkeys create -u tec -e 99y --reusable`
    authKeyFile = config.age.secrets.tailscale-preauth.path;
    extraUpFlags = [
      "--login-server=https://${config.site.apps.headscale.subdomain}.${config.site.domain}"
      "--accept-dns=false" # No need for MagicDNS
      "--advertise-exit-node"
      "--reset"
    ];
  };

  services.networkd-dispatcher = {
    enable = true;
    rules."50-tailscale" = {
      onState = ["routable"];
      script = "${lib.getExe pkgs.ethtool} -K enp1s0 rx-udp-gro-forwarding on rx-gro-list off";
    };
  };
}

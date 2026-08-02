{ config, lib, pkgs, ... }:

# A static mesh for inter-node traffic, off the tailnet so it depends on no
# service the cluster hosts.

let
  inherit (config.site.mesh) subnet port;
  this-host = config.site.server.host;
  hosts = lib.sort (a: b: a < b) config.site.hosts;
  address = name:
    let index = lib.lists.findFirstIndex (n: n == name) null hosts;
    in if index == null
       then throw "wireguard-mesh: ${name} is not in site.hosts"
       else "${subnet}${toString (1 + index)}";
  key-file = name: ../secrets/keys + "/wg-${name}.pub";
  public-key = name: lib.removeSuffix "\n" (builtins.readFile (key-file name));
  unkeyed = lib.filter (name: !builtins.pathExists (key-file name)) hosts;
  mkPeer = name: {
    PublicKey = public-key name;
    AllowedIPs = [ "${address name}/128" ];
    Endpoint = "_${name}.${config.site.domain}:${toString port}";
    PersistentKeepalive = 25;
  };
in
{
  assertions = [
    { assertion = unkeyed == [ ];
      message = "wireguard-mesh: no key for ${lib.concatStringsSep ", " unkeyed}; "
                + "run `./secrets/make.sh wireguard`, then `git add secrets/keys`";
    }
  ];

  age.secrets."wg-${this-host}" = {
    file = ../secrets/keys + "/wg-${this-host}.age";
    # Ownership systemd.netdev(5) asks for.
    owner = "root";
    group = "systemd-network";
    mode = "0640";
  };

  networking.firewall.allowedUDPPorts = [ port ];

  environment.systemPackages = [ pkgs.wireguard-tools ];

  systemd.network = {
    netdevs."50-wg0" = {
      netdevConfig = {
        Kind = "wireguard";
        Name = "wg0";
      };
      wireguardConfig = {
        ListenPort = port;
        PrivateKeyFile = config.age.secrets."wg-${this-host}".path;
      };
      wireguardPeers = map mkPeer (lib.filter (n: n != this-host) hosts);
    };
    networks."50-wg0" = {
      matchConfig.Name = "wg0";
      address = [ "${address this-host}/64" ];
      linkConfig.RequiredForOnline = "no";
    };
    wait-online.ignoredInterfaces = [ "wg0" ];
  };
}

{ config, lib, pkgs, ... }:

# A static mesh for inter-node traffic, off the tailnet so it depends on no
# service the cluster hosts.

let
  inherit (config.site) hosts;
  inherit (config.site.mesh) subnet port;
  this-host = config.site.server.host;
  # The low 16 bits of the name's digest, as the hex group they already are.
  address = name: "${subnet}${builtins.substring 0 4 (builtins.hashString "sha256" name)}";
  key-file = name: ../secrets/keys + "/wg-${name}.pub";
  public-key = name: lib.removeSuffix "\n" (builtins.readFile (key-file name));
  unkeyed = lib.filter (name: !builtins.pathExists (key-file name)) hosts;
  mkPeer = name: {
    PublicKey = public-key name;
    AllowedIPs = [ "${address name}/128" ];
    Endpoint = "${name}.${config.site.dns.host-domain}.${config.site.domain}:${toString port}";
    # 15s rather than the conventional 25s: dns-pooler reads liveness from the
    # per-peer receive counter, which only advances as fast as keepalives arrive.
    PersistentKeepalive = 15;
  };
in
{
  assertions = [
    { assertion = unkeyed == [ ];
      message = "wireguard-mesh: no key for ${lib.concatStringsSep ", " unkeyed}; "
                + "run `./secrets/make.sh wireguard`, then `git add secrets/keys`";
    }
    (let collided = lib.filter
           (name: lib.any (other: other != name && address other == address name) hosts)
           hosts;
     in { assertion = collided == [ ];
          message = "wireguard-mesh: ${lib.concatStringsSep ", " collided} share a mesh "
                    + "address; rename one, or widen the host bits in site.mesh.subnet";
        })
    { assertion = lib.elem this-host hosts;
      message = "wireguard-mesh: ${this-host} is not in site.hosts, so it has no mesh address";
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

  networking.hosts = lib.listToAttrs
    (map (name: lib.nameValuePair (address name) [ "${name}.internal" ]) hosts);

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

{ ... }:

{
  networking.firewall.allowedTCPPorts = [ 22 80 443 ];

  # If I end up wanting to add plugins, see:
  # https://mdleom.com/blog/2021/12/27/caddy-plugins-nixos/
  services.caddy = {
    enable = true;
    virtualHosts."tecosaur.net".extraConfig = ''
respond "Hello, world!"
  '';
    virtualHosts."git.tecosaur.net".extraConfig = ''
reverse_proxy localhost:3000
  '';
  };
}

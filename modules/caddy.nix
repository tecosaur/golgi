{ config, lib, pkgs, ... }:

let
  dynamicdns-config = if config.site.server.authoritative then
    ''
    domains {
            ${config.site.domain} @ * ${config.site.cloudflare-bypass-subdomain}
    }
    ''
    else
    ''
    domains {
            ${config.site.domain}
    }
    dynamic_domains
    '';
in {
  networking.firewall.allowedTCPPorts = [ 80 443 ];
  networking.firewall.allowedUDPPorts = [ 443 ];

  age.secrets.cloudflare-api-env = {
    owner = "caddy";
    group = "users";
    file = ../secrets/cloudflare-api-env.age;
  };

  services.caddy = {
      enable = true;
      package = pkgs.callPackage ../packages/caddy.nix {
        externalPlugins = [
          {name = "cloudflare"; repo = "github.com/caddy-dns/cloudflare";
           version = "89f16b99c18ef49c8bb470a82f895bce01cbaece";}
          {name = "dynamicdns"; repo = "github.com/mholt/caddy-dynamicdns";
           version = "7c818ab3fc3485a72a346f85c77810725f19f9cf";}
          {name = "caddy-fs-git"; repo = "github.com/tecosaur/caddy-fs-git";
           version = "ef9d0ab232f4fe5d7e86312cbba45ff8afea98a1";}
          {name = "replace-response"; repo = "github.com/caddyserver/replace-response";
           version = "f92bc7d0c29d0588f91f29ecb38a0c4ddf3f85f8";}
        ];
        vendorHash = "sha256-cQ+E1nSIo4Hnmc7NsZHXmgHE7ZWGU6w1jicQKzATCXc=";
      };
      globalConfig =
        ''
        acme_dns cloudflare {env.CLOUDFLARE_AUTH_TOKEN}
        dynamic_dns {
                provider cloudflare {env.CLOUDFLARE_AUTH_TOKEN}
                ${dynamicdns-config}
        }
        '';
      virtualHosts."*.${config.site.domain}" = lib.mkIf config.site.server.authoritative {
        extraConfig =
          ''
          respond "In the beginning, there was darkness." 404
          '';
      };
  };

  systemd.services.caddy.serviceConfig = {
    EnvironmentFile = config.age.secrets.cloudflare-api-env.path;
  };
}

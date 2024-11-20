{ config, lib, pkgs, ... }:

with lib;

let
  static-root = pkgs.runCommand "static-root" { buildInputs = [ pkgs.gettext ]; } ''
      export DOMAIN='${config.site.domain}'
      export FORGE_SUBDOMAIN='${config.site.apps.forgejo.subdomain}'
      export HOMEPAGE_SUBDOMAIN='${config.site.apps.homepage.subdomain}'
      export APPS_TEXT=$(cat <<'HEREDOC'
      ${concatStringsSep "\n" (map (app: "• ${app.name} (${app.description})")
        (builtins.filter (app: app.enabled) (builtins.attrValues config.site.apps)))}
      HEREDOC
      )

      apply_template() {
          for file in "$@"; do
              tmpout=$(mktemp)
              envsubst < "$file" > "$tmpout"
              mv "$tmpout" "$file"
          done
      }

      mkdir -p $out
      cp -r ${../assets/site}/* $out
      cd $out
      apply_template index.txt welcome-public.html welcome-private.html
      cp index.html index-public.html
      export WELCOME=`sed 's/^/            /g' welcome-public.html`
      apply_template index-public.html
      cp index.html index-private.html
      export WELCOME=`sed 's/^/            /g' welcome-private.html`
      apply_template index-private.html
      rm index.html welcome-public.html welcome-private.html
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
          {name = "caddy-fs-git"; repo = "github.com/tecosaur/caddy-fs-git";
           version = "ef9d0ab232f4fe5d7e86312cbba45ff8afea98a1";}
          {name = "replace-response"; repo = "github.com/caddyserver/replace-response";
           version = "f92bc7d0c29d0588f91f29ecb38a0c4ddf3f85f8";}
        ];
        vendorHash = "sha256-DoWPvOAAHOLBhlOvOXTlMHMZ9LTKhYAVUbIR/5YVMB8=";
      };
      globalConfig =
        ''
        acme_dns cloudflare {env.CLOUDFLARE_AUTH_TOKEN}
        '';
      virtualHosts."${config.site.domain}".extraConfig = ''
        @browser-auth {
            header User-Agent *Mozilla*
            header Cookie *authelia_session*
        }
        @browser header User-Agent *Mozilla*
        route {
            file_server @browser-auth {
              root ${static-root}
              index index-private.html
            }
            file_server @browser {
              root ${static-root}
              index index-public.html
            }
            file_server {
              root ${static-root}
              index index.txt
            }
        }
        '';
      virtualHosts."*.${config.site.domain}".extraConfig =
        ''
        respond "In the beginning, there was darkness." 404
        '';
  };

  systemd.services.caddy.serviceConfig = {
    EnvironmentFile = config.age.secrets.cloudflare-api-env.path;
  };

  users.users.caddy = {
    extraGroups =
      lib.optional config.services.syncthing.enable config.services.syncthing.user ++
      lib.optional config.services.forgejo.enable   config.services.forgejo.user;
  };
}

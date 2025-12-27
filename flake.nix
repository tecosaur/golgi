{
  description = "Deployable system configurations";

  inputs = {
    nixpkgs.url = github:NixOS/nixpkgs/nixos-unstable;
    flake-utils-plus.url = github:gytis-ivaskevicius/flake-utils-plus;
    agenix.url = "github:ryantm/agenix";
    crowdsec = {
      url = "git+https://codeberg.org/kampka/nix-flake-crowdsec.git";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    declarative-jellyfin.url = "github:Sveske-Juice/declarative-jellyfin";
    declarative-jellyfin.inputs.nixpkgs.follows = "nixpkgs";
    deploy-rs = {
      url = github:serokell/deploy-rs;
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  nixConfig.sandbox = "relaxed";

  outputs = inputs@{ self, nixpkgs, flake-utils-plus, agenix, crowdsec, declarative-jellyfin, ... }:
    let
      modules = flake-utils-plus.lib.exportModules (
        nixpkgs.lib.mapAttrsToList (name: value: ./modules/${name}) (builtins.readDir ./modules)
      );
      site-config = import ./site.nix;
      site-setup = {
        domain = "tecosaur.net";
        server.admin = {
          hashedPassword = "$6$ET8BLqODvw77VOmI$oun2gILUqBr/3WonH2FO1L.myMIM80KeyO5W1GrYhJTo./jk7XcG8B3vEEcbpfx3R9h.sR0VV187/MgnsnouB1";
          authorizedKeys = [ "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOZZqcJOLdN+QFHKyW8ST2zz750+8TdvO9IT5geXpQVt tec@tranquillity" ];
        };
        email = {
          server = "smtp.fastmail.com";
          username = "tec@tecosaur.net";
        };
        apps = {
          mealie.subdomain = "food";
          microbin = {
            title = "μPaste";
            subdomain = "pastes";
            short-subdomain = "p";
            user-group = "paste";
          };
          forgejo = {
            user-group = "forge";
          };
          headscale.enabled = true;
          # calibre-web.enabled = true;
          paperless.enabled = true;
          sftpgo.enabled = true;
          immich.enabled = true;
          jellyfin.enabled = true;
        };
      };
    in
    flake-utils-plus.lib.mkFlake {
      inherit self inputs modules;

      hosts.golgi.modules = with modules; [
          agenix.nixosModules.default
          auth
          caddy
          crowdsec.nixosModules.crowdsec
          crowdsec.nixosModules.crowdsec-firewall-bouncer
          crowdsec-setup
          fava
          forgejo
          hardware-hetzner
          headscale
          homepage
          ntfy
          mealie
          memos
          microbin
          site-config
          site-root
          syncthing
          system
          tailscale
          uptime
          vikunja
          zsh
          {
            site = nixpkgs.lib.recursiveUpdate site-setup {
              server = {
                host = "golgi";
                authoritative = true;
                ipv6 = "2a01:4ff:f0:cc83";
              };
            };
          }
        ];

      hosts.nucleus.modules = with modules; [
        agenix.nixosModules.default
        caddy
        crowdsec-setup
        crowdsec.nixosModules.crowdsec
        crowdsec.nixosModules.crowdsec-firewall-bouncer
        declarative-jellyfin.nixosModules.default
        hardware-nas
        home-assistant
        immich
        lyrion
        sftpgo
        site-config
        streaming
        system
        tailscale
        zsh
        {
          site = nixpkgs.lib.recursiveUpdate site-setup {
            server.host = "nucleus";
          };
        }
      ];

      deploy.nodes = {
        golgi = {
          hostname = "${self.nixosConfigurations.golgi.config.site.cloudflare-bypass-subdomain}.${self.nixosConfigurations.golgi.config.site.domain}";
          fastConnection = false;
          profiles = {
            system = {
              sshUser = "admin";
              sshOpts = ["-S" "none"];
              path =
                inputs.deploy-rs.lib.x86_64-linux.activate.nixos self.nixosConfigurations.golgi;
              user = "root";
            };
          };
        };
        nucleus = {
          hostname = "nas.lan";
          fastConnection = false;
          profiles = {
            system = {
              sshUser = "admin";
              sshOpts = ["-S" "none"];
              path =
                inputs.deploy-rs.lib.x86_64-linux.activate.nixos self.nixosConfigurations.nucleus;
              user = "root";
            };
          };
        };
      };

      outputsBuilder = (channels: {
        devShells.default = channels.nixpkgs.mkShell {
          name = "deploy";
          buildInputs = with channels.nixpkgs; [
            nixVersions.latest
            inputs.deploy-rs.packages.${system}.default
          ];
        };
      });

      checks = builtins.mapAttrs (system: deployLib: deployLib.deployChecks self.deploy) inputs.deploy-rs.lib;
    };
}

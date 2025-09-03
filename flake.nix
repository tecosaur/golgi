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
    deploy-rs = {
      url = github:serokell/deploy-rs;
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  nixConfig.sandbox = "relaxed";

  outputs = inputs@{ self, nixpkgs, flake-utils-plus, agenix, crowdsec, ... }:
    let
      modules = flake-utils-plus.lib.exportModules (
        nixpkgs.lib.mapAttrsToList (name: value: ./modules/${name}) (builtins.readDir ./modules)
      );
      site-config = import ./site.nix;
      app-setup = {
        mealie.subdomain = "food";
        microbin = {
          title = "μPaste";
          subdomain = "pastes";
          short-subdomain = "p";
          user-group = "paste";
        };
        forgejo = {
          subdomain = "code";
          user-group = "forge";
        };
        headscale.magicdns-subdomain = "on";
        lldap.subdomain = "users";
        sftpgo.enabled = true;
        immich.enabled = true;
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
            site = {
              domain = "tecosaur.net";
              server = {
                authoritative = true;
                ipv6 = "2a01:4ff:f0:cc83";
              };
              apps = app-setup;
            };
          }
        ];

      hosts.nucleus.modules = with modules; [
        agenix.nixosModules.default
        caddy
        crowdsec-setup
        crowdsec.nixosModules.crowdsec
        crowdsec.nixosModules.crowdsec-firewall-bouncer
        hardware-nas
        home-assistant
        immich
        sftpgo
        site-config
        system
        tailscale
        zsh
        {
          site = {
            domain = "tecosaur.net";
            server.host = "nucleus";
            apps = {
              home-assistant.subdomain = "doonan";
            };
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
              sshOpts = ["-o" "ControlMaster=no"];
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
              sshOpts = ["-o" "ControlMaster=no"];
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

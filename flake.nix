{
  description = "Golgi flake";

  inputs = {
    nixpkgs.url = github:NixOS/nixpkgs/nixos-unstable;
    flake-utils-plus.url = github:gytis-ivaskevicius/flake-utils-plus;
    agenix.url = "github:ryantm/agenix";
    deploy-rs = {
      url = github:serokell/deploy-rs;
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  nixConfig.sandbox = "relaxed";

  outputs = inputs@{ self, nixpkgs, flake-utils-plus, agenix, ... }:
    let
      modules = flake-utils-plus.lib.exportModules (
        nixpkgs.lib.mapAttrsToList (name: value: ./modules/${name}) (builtins.readDir ./modules)
      );
      site-config = import ./site.nix;
    in
    flake-utils-plus.lib.mkFlake {
      inherit self inputs modules;

      hosts.golgi.modules = with modules; [
          agenix.nixosModules.default
          auth
          caddy
          forgejo
          hardware-hetzner
          headscale
          homepage
          mealie
          microbin
          site-config
          site-root
          syncthing
          system
          tailscale
          uptime
          zsh
          {
            site = {
              domain = "tecosaur.net";
              server = {
                authoritative = true;
                ipv6 = "2a01:4ff:f0:cc83::";
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
                  subdomain = "code";
                  user-group = "forge";
                };
                headscale.magicdns-subdomain = "on";
                lldap.subdomain = "users";
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
      };

      outputsBuilder = (channels: {
        devShells.default = channels.nixpkgs.mkShell {
          name = "deploy";
          buildInputs = with channels.nixpkgs; [
            nixVersions.latest
            inputs.deploy-rs.defaultPackage.${system}
          ];
        };
      });

      checks = builtins.mapAttrs (system: deployLib: deployLib.deployChecks self.deploy) inputs.deploy-rs.lib;
    };
}

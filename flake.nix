{
  description = "My server flake";

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
      globalConfig = { config, lib, ... }: {
        options.globals = {
          domain = lib.mkOption {
            type = lib.types.str;
            default = "example.com";
            description = "Global domain for the server";
          };
        };
        config.globals = {
          domain = "tecosaur.net";
        };
      };
    in
    flake-utils-plus.lib.mkFlake {
      inherit self inputs modules;

      hosts = {
        golgi.modules = with modules; [
          admin
          agenix.nixosModules.default
          authelia
          caddy
          common
          forgejo
          globalConfig
          hardened
          hardware-hetzner
          headscale
          syncthing
          zsh
        ];
      };

      deploy.nodes = {
        golgi = {
          hostname = self.nixosConfigurations.golgi.config.globals.domain;
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

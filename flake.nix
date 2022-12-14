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

  outputs = inputs@{ self, nixpkgs, flake-utils-plus, agenix, ... }:
    let
      modules = flake-utils-plus.lib.exportModules (
        nixpkgs.lib.mapAttrsToList (name: value: ./modules/${name}) (builtins.readDir ./modules)
      );
    in
    flake-utils-plus.lib.mkFlake {
      inherit self inputs modules;

      hosts = {
        golgi.modules = with modules; [
          common
          admin
          hardware-hetzner
          agenix.nixosModule
          gitea
          caddy
        ];
      };

      deploy.nodes = {
        golgi = {
          hostname = "tecosaur.net";
          fastConnection = false;
          profiles = {
            system = {
              sshUser = "admin";
              path =
                inputs.deploy-rs.lib.x86_64-linux.activate.nixos self.nixosConfigurations.golgi;
              user = "root";
            };
          };
        };
      };

      outputsBuilder = (channels: {
        devShells.default = channels.nixpkgs.mkShell {
          name = "my-deploy-shell";
          buildInputs = with channels.nixpkgs; [
            nixUnstable
            inputs.deploy-rs.defaultPackage.${system}
          ];
        };
      });

      checks = builtins.mapAttrs (system: deployLib: deployLib.deployChecks self.deploy) inputs.deploy-rs.lib;
    };
}

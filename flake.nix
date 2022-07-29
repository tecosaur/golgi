{
  description = "My server flake";

  inputs = {
    nixpkgs.url = github:NixOS/nixpkgs/nixos-22.05;
    flake-utils-plus.url = github:gytis-ivaskevicius/flake-utils-plus;
    deploy-rs = {
      url = github:serokell/deploy-rs;
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs@{ self, nixpkgs, flake-utils-plus, ... }:
    let
      nixosModules = flake-utils-plus.lib.exportModules (
        nixpkgs.lib.mapAttrsToList (name: value: ./nixosModules/${name}) (builtins.readDir ./nixosModules)
      );
    in
    flake-utils-plus.lib.mkFlake {
      inherit self inputs nixosModules;

      hosts = {
        golgi.modules = with nixosModules; [
          common
          admin
          hardware-hetzner
          # docker
        ];
      };

      deploy.nodes = {
        my-node = {
          hostname = "5.161.98.27";
          fastConnection = false;
          profiles = {
            my-profile = {
              sshUser = "admin";
              path =
                inputs.deploy-rs.lib.x86_64-linux.activate.nixos self.nixosConfigurations.golgi;
              user = "root";
            };
          };
        };
      };

      outputsBuilder = (channels: {
        devShell = channels.nixpkgs.mkShell {
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

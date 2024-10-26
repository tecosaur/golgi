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
          auth-domain = lib.mkOption {
            type = lib.types.str;
            default = "auth.example.com";
            description = "OAuth2/OICD domain";
          };
          cloudflare-bypass = lib.mkOption {
            type = lib.types.str;
            default = config.globals.domain;
            description = "Domain to use for bypassing Cloudflare (e.g. for SSH).";
          };
        };
        config.globals = {
          domain = "tecosaur.net";
          auth-domain = "auth.${config.globals.domain}";
          cloudflare-bypass = "ssh.${config.globals.domain}";
        };
      };
    in
    flake-utils-plus.lib.mkFlake {
      inherit self inputs modules;

      hosts = {
        golgi.modules = with modules; [
          agenix.nixosModules.default
          auth
          caddy
          forgejo
          globalConfig
          headscale
          pastebin
          syncthing
          system
          uptime
          zsh
        ];
      };

      deploy.nodes = {
        golgi = {
          hostname = "${self.nixosConfigurations.golgi.config.globals.cloudflare-bypass}";
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

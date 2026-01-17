{
  description = "Deployable system configurations";

  inputs = {
    nixpkgs.url = github:NixOS/nixpkgs/nixos-unstable;
    flake-utils-plus.url = github:gytis-ivaskevicius/flake-utils-plus;
    agenix.url = "github:ryantm/agenix";
    declarative-jellyfin.url = "github:Sveske-Juice/declarative-jellyfin";
    declarative-jellyfin.inputs.nixpkgs.follows = "nixpkgs";
    deploy-rs = {
      url = github:serokell/deploy-rs;
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  nixConfig.sandbox = "relaxed";

  outputs = inputs@{ self, nixpkgs, flake-utils-plus, agenix, declarative-jellyfin, ... }:
    let
      site-config = import ./site.nix;
      modules = flake-utils-plus.lib.exportModules (
        nixpkgs.lib.mapAttrsToList (name: value: ./modules/${name}) (builtins.readDir ./modules)
      );
      core-modules = with modules; [
        agenix.nixosModules.default
        beszel-agent
        caddy
        site-config
        system
        tailscale
        zsh
      ];
      machines = {
        golgi = {
          server = {
            authoritative = true;
            ipv6 = "2a01:4ff:f0:cc83";
          };
          modules = with modules; [
            auth
            beszel-hub
            fava
            forgejo
            hardware-hetzner
            headscale
            homepage
            ntfy
            mealie
            memos
            microbin
            site-root
            syncthing
            uptime
            vikunja
          ];
        };
        nucleus.modules = with modules; [
          declarative-jellyfin.nixosModules.default
          hardware-nas
          home-assistant
          immich
          llm
          lyrion
          paperless
          scrutiny
          sftpgo
          speedtest
          streaming
          warracker
        ];
      };
      global-enabled-apps = (nixpkgs.lib.concatMapAttrs (machine: setup:
        (nixpkgs.lib.foldlAttrs
          (acc: app: conf:
            if conf.enabled then
              acc // { "${app}" = {enabled = true; host = machine; }; }
            else acc)
          { }
          (nixpkgs.lib.nixosSystem {
            system = "x86_64-linux";
            modules = [ flake-utils-plus.nixosModules.autoGenFromInputs ] ++
                      core-modules ++ setup.modules ++
                      [ { site.domain = "_"; } ];
          }).config.site.apps))
        machines);
      site-setup = {
        domain = "tecosaur.net";
        cloudflare-bypass-subdomain = "ssh";
        server.admin = {
          hashedPassword = "$6$ET8BLqODvw77VOmI$oun2gILUqBr/3WonH2FO1L.myMIM80KeyO5W1GrYhJTo./jk7XcG8B3vEEcbpfx3R9h.sR0VV187/MgnsnouB1";
          authorizedKeys = [ "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOZZqcJOLdN+QFHKyW8ST2zz750+8TdvO9IT5geXpQVt tec@tranquillity" ];
        };
        email = {
          server = "smtp.fastmail.com";
          username = "tec@tecosaur.net";
        };
        accent = {
          primary = "#239a58";
          secondary = "#67bc85";
        };
        apps = nixpkgs.lib.recursiveUpdate global-enabled-apps {
          beszel.publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIL6RP5omIbCzQsC/NizUg56JgpgMdl0/VXmCAE0VyJlq";
          mealie.subdomain = "food";
          memos.groups.extra = [ "family" ];
          microbin = {
            title = "μPaste";
            subdomain = "pastes";
            short-subdomain = "p";
            groups.primary = "paste";
          };
          forgejo = {
            groups.primary = "forge";
            site-name = "Code by TEC";
            site-description = "The personal Forgejo instance of TEC";
            default-user-redirect = "tec";
            served-repositories = [
              {
                repo = "tec/this-month-in-org";
                rev = "html";
                subdomain = "blog";
                path = "tmio";
              }
            ];
          };
          home-assistant.subdomain = "doonan";
          paperless.groups.extra = [ "family" ];
          sftpgo.groups.extra = [ "family" ];
          immich.groups.extra = [ "family" ];
          jellyfin.groups.extra = [ "family" ];
          warracker.groups.extra = [ "family" ];
        };
      };
    in flake-utils-plus.lib.mkFlake {
      inherit self inputs modules;

      hosts = (builtins.mapAttrs
        (name: setup: {
          modules = core-modules ++ setup.modules ++ [{
            site = nixpkgs.lib.recursiveUpdate site-setup {
              server = (setup.server or { }) // { host = name; };
            };
          }];
        })
        machines);

      deploy.nodes = (builtins.mapAttrs
        (name: _: {
          hostname = "_${name}.${site-setup.domain}";
          fastConnection = false;
          profiles.system = {
            sshUser = "admin";
            sshOpts = [ "-S" "none" ];
            path = inputs.deploy-rs.lib.x86_64-linux.activate.nixos self.nixosConfigurations."${name}";
            user = "root";
          };
        })
        machines);

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

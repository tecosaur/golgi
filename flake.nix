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
        dns-pooler
        site-config
        system
        tailscale
        wireguard-mesh
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
            hardware-hetzner
            headscale
            homepage
            ntfy
            mealie
            memos
            microbin
            rustical
            site-root
            syncthing
            uptime
            vikunja
          ];
        };
        nucleus = {
          apps.llm.proxy = [ "tranquillity.lan:5521" ];
          modules = with modules; [
            data-mounts
            declarative-jellyfin.nixosModules.default
            hardware-nas
            home-assistant
            dawarich
            forgejo
            immich
            llm
            lyrion
            paperless
            scrobbler
            scrutiny
            sftpgo
            site-root
            speedtest
            storyteller
            streaming
            tandoor
            trek
            warracker
          ];
        };
      };
      # Every machine evaluated with its real site settings, short of what is
      # computed from all of them, for the facts one host's configuration
      # needs about the others.
      machine-systems = nixpkgs.lib.mapAttrs
        (name: setup: (nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = { inherit inputs; };
          modules = [ flake-utils-plus.nixosModules.autoGenFromInputs ] ++
                    core-modules ++ setup.modules ++
                    [ { site = machine-site name setup; } ];
        }))
        machines;
      global-enabled-apps = nixpkgs.lib.concatMapAttrs (machine: sys:
        (nixpkgs.lib.foldlAttrs
          (acc: app: conf:
            if conf.enabled then
              acc // { "${app}" = {
                         enabled = true;
                         host = machine;
                         serviceConfig = if conf.service == null then { } else
                           sys.config.systemd.services."${conf.service}".serviceConfig;
                       }; }
            else acc)
          { }
          sys.config.site.apps))
        machine-systems;
      # The names each machine's Caddy serves, relative to the domain ("@" the
      # apex): a virtual host key may list several addresses, with a scheme or
      # port, and only those under the site domain are ours.
      global-served-names = nixpkgs.lib.mapAttrs (_: sys:
        let
          inherit (nixpkgs) lib;
          domain = site-setup.domain;
          relative = address:
            let host = lib.head (lib.splitString ":"
                  (lib.removePrefix "https://" (lib.removePrefix "http://" address)));
            in if host == domain then [ "@" ]
               else lib.optional (lib.hasSuffix ".${domain}" host) (lib.removeSuffix ".${domain}" host);
          addresses = key: lib.filter (a: a != "")
            (lib.splitString " " (lib.replaceStrings [ "," ] [ " " ] key));
        in lib.unique (lib.concatMap (key: lib.concatMap relative (addresses key))
          (lib.attrNames sys.config.services.caddy.virtualHosts)))
        machine-systems;
      # One machine's site settings, everything but what is computed across
      # machines (global-enabled-apps, dns.served).
      machine-site = name: setup: nixpkgs.lib.recursiveUpdate site-setup {
        hosts = builtins.attrNames machines;
        server = (setup.server or { }) // { host = name; };
        apps = nixpkgs.lib.recursiveUpdate site-setup.apps (setup.apps or { });
      };
      site-setup = {
        domain = "tecosaur.net";
        dns = {
          records = let
            mail = name: [
              { inherit name; type = "MX"; value = "10 in1-smtp.messagingengine.com."; }
              { inherit name; type = "MX"; value = "20 in2-smtp.messagingengine.com."; }
            ];
            dkim = n: { name = "fm${n}._domainkey"; type = "CNAME";
                        value = "fm${n}.tecosaur.net.dkim.fmhosted.com."; };
          in mail "@" ++ mail "*" ++ mail "www" ++ map dkim [ "1" "2" "3" ] ++ [
            { name = "@"; type = "TXT"; value = "v=spf1 include:spf.messagingengine.com ?all"; }
            { name = "ssh"; type = "CNAME"; value = "golgi.hosts.tecosaur.net."; }
          ];
        };
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
        apps = {
          beszel.publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIL6RP5omIbCzQsC/NizUg56JgpgMdl0/VXmCAE0VyJlq";
          dawarich.groups = { primary = "timeline"; extra = [ "family" ]; };
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
            qa-captcha = {
              enabled = true;
              questions = [
                "What is my first name?"
                "What is the thing I use as my avatar?"
                "What is the mononym I often go by online?"
                "What community do you know me from?"
              ];
              answers = [
                "timothy"
                "tec"
                "tree"
                "tecosaur"
                "julia"
                "julialang"
                "emacs"
                "org"
                "doom"
              ];
            };
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
          rustical.groups = { primary = "caldav"; extra = [ "family" ]; };
          sftpgo.groups.extra = [ "family" ];
          storyteller.groups.extra = [ "family" ];
          tandoor.groups.extra = [ "family" ];
          immich.groups.extra = [ "family" ];
          jellyfin.groups.extra = [ "family" ];
          koito = {
            title = "Listens";
            groups.primary = "listens";
          };
          multi-scrobbler = {
            jellyfin-user = "tec";
            listenbrainz-user = "tecosaur";
          };
          warracker.groups.extra = [ "family" ];
        };
      };
    in flake-utils-plus.lib.mkFlake {
      inherit self inputs modules;

      hosts = (builtins.mapAttrs
        (name: setup: {
          modules = core-modules ++ setup.modules ++ [{
            site = nixpkgs.lib.recursiveUpdate (machine-site name setup) {
              apps = nixpkgs.lib.recursiveUpdate global-enabled-apps
                (machine-site name setup).apps;
              dns.served = global-served-names;
            };
          }];
        })
        machines);

      deploy.nodes = (builtins.mapAttrs
        (name: _: {
          hostname = with self.nixosConfigurations.${name}.config.site;
            "${name}.${dns.host-domain}.${domain}";
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

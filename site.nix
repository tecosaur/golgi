{ config, lib, pkgs, ... }:

let
  mkAppOption = { name, description, homepage, simpleicon ? null,
                  service ? (lib.toLower (lib.replaceStrings [ " " ] [ "-" ] name)),
                  usesStateDir ? (service != null),
                  subdomain, port, admin ? "admin", extra-groups ? [],
                  auth ? {}, cacheSubdirs ? [], stateSubdirs ? null, extraOptions ? {} }:
    {
      name = lib.mkOption {
        type = lib.types.str;
        default = name;
        description = "How ${name} is known by.";
      };
      description = lib.mkOption {
        type = lib.types.str;
        default = description;
        description = "Description of the ${name} app";
      };
      homepage = lib.mkOption {
        type = lib.types.str;
        default = homepage;
        description = "Link to the homepage/documentation for ${name}";
      };
      simpleicon = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = simpleicon;
        description = "Simple icon for the ${name} app";
      };
      enabled = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Whether ${name} has been enabled, set by modules enabling it";
      };
      service = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = service;
        description = "The systemd service for the ${name} app. Set to null if stateless";
      };
      usesStateDir = lib.mkOption {
        type = lib.types.bool;
        default = usesStateDir;
        description = "Whether the ${name} app uses a state directory";
      };
      serviceConfig = lib.mkOption {
        type = lib.types.attrs;
        default = { };
        description = "The systemd service configuration for the ${name} app";
      };
      host = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Host that the ${name} app is running on";
      };
      subdomain = lib.mkOption {
        type = lib.types.str;
        default = subdomain;
        description = "Name for the ${name} app";
      };
      dir = lib.mkOption {
        type = lib.types.str;
        default = "/var/lib/${lib.toLower (if service != null then service else name)}";
        description = "Directory where the ${name} app stores its data";
      };
      cacheSubdirs = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = cacheSubdirs;
        description = "List of subdirectories in the ${name} app data directory to be treated as cache";
      };
      stateSubdirs = lib.mkOption {
        type = lib.types.nullOr (lib.types.listOf lib.types.str);
        default = stateSubdirs;
        example = [ "data" "uploads" ];
        description = ''
          Subdirectories of the ${name} app state directory holding data worth
          keeping, when only some of it is. Null puts the whole state directory
          on bulk storage, which is right until part of it is derived.
        '';
      };
      port = lib.mkOption {
        type = lib.types.int;
        default = port;
        description = "Port that the ${name} app listens on";
      };
      groups = {
        admin = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = admin;
          description = "User group that has admin access to the ${name} app";
        };
        primary = lib.mkOption {
          type = lib.types.str;
          default = lib.toLower name;
          description = "Primary user group for the ${name} app";
        };
        extra = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = extra-groups;
          description = "Additional user groups that have access to the ${name} app";
        };
      };
    } // extraOptions;
  assets-pkg = pkgs.callPackage ./packages/site-assets.nix {
    primary = config.site.accent.primary;
    secondary = config.site.accent.secondary;
  };
in {
  options.site = {
    domain = lib.mkOption {
      type = lib.types.str;
      description = "Global domain name for the site";
    };
    hosts = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Every machine in the site, this one included";
    };
    mesh = {
      subnet = lib.mkOption {
        type = lib.types.str;
        default = "fd00:c1de::";
        description = ''
          IPv6 ULA prefix for the inter-node mesh. Hosts are numbered from 1
          in the order they sort, so this must not collide with the tailnet.
        '';
      };
      port = lib.mkOption {
        type = lib.types.int;
        default = 51820;
        description = "Port the mesh listens on, opened to UDP on every host";
      };
    };
    cloudflare-bypass-subdomain = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Domain to use for bypassing Cloudflare (e.g. for SSH).";
    };
    accent = {
      primary = lib.mkOption {
        type = lib.types.str;
        default = "#4F46E5";
        description = "Primary accent color in hex format";
      };
      secondary = lib.mkOption {
        type = lib.types.str;
        default = "#9333EA";
        description = "Secondary accent color in hex format";
      };
    };
    assets = lib.mkPackageOption { site-assets = assets-pkg; } "site-assets" { };
    server = {
      admin = {
        hashedPassword = lib.mkOption {
          type = lib.types.str;
          default = "";
          description = "Hashed password for the admin user";
        };
        authorizedKeys = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [];
          description = "SSH public keys for the admin user";
        };
      };
      authoritative = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Whether this server is authoritative for the domain";
      };
      host = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Server name";
      };
      ipv6 = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "IPv6 address for the server";
      };
      ipversions = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = ["ipv4" "ipv6"];
        description = "what versions of ip to use: ipv4 and/or ipv6";
      };
    };
    email = {
      server = lib.mkOption {
        type = lib.types.str;
        default = "smtp.example.com";
        description = "SMTP server to use for sending email";
      };
      port = lib.mkOption {
        type = lib.types.int;
        default = 587;
        description = "Port to use for the SMTP server";
      };
      username = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Username for the SMTP server";
      };
    };
    apps = {
      authelia = mkAppOption {
        name = "Authelia";
        homepage = "https://www.authelia.com";
        description = "authentication and SSO portal";
        simpleicon = "authelia";
        service = null; # "authelia-main";
        subdomain = "auth";
        port = 9091;
      };
      beszel = mkAppOption {
        name = "Beszel";
        homepage = "https://beszel.dev";
        description = "System monitoring";
        service = "beszel-hub";
        subdomain = "systems";
        port = 8090;
        admin = null;
        extra-groups = [ "admin" ];
        extraOptions = {
          publicKey = lib.mkOption {
            type = lib.types.str;
            default = "";
            description = "Public key of the Beszel hub";
          };
          agent-port = lib.mkOption {
            type = lib.types.int;
            default = 45876;
            description = "Port that the Beszel agent listens on";
          };
          extra-filesystems = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ ];
            description = "Additional filesystems the agent should monitor";
          };
          systems = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ ];
            description = "List of system hosts, that have Beszel agents";
          };
        };
      };
      dawarich = mkAppOption {
        name = "Dawarich";
        homepage = "https://dawarich.com";
        description = "location timeline";
        service = "dawarich-web";
        subdomain = "timeline";
        port = 6805;
      };
      fava = mkAppOption {
        name = "Fava";
        homepage = "https://beancount.github.io/fava/";
        description = "Beancount web interface";
        service = null;
        subdomain = "fava";
        port = 5025;
      };
      forgejo = mkAppOption {
        name = "Forgejo";
        homepage = "https://forgejo.org";
        description = "personal software forge";
        simpleicon = "forgejo";
        subdomain = "code";
        port = 3000;
        extraOptions = {
          site-name = lib.mkOption {
            type = lib.types.str;
            default = "Forgejo";
            description = "Name of the Forgejo instance";
          };
          site-description = lib.mkOption {
            type = lib.types.str;
            default = "Forgejo instance";
            description = "Description of the Forgejo instance";
          };
          default-user-redirect = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "A private user to redirect to upon visiting the root domain";
          };
          qa-captcha = {
            enabled = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = "Whether to enable the question and answer captcha for the Forgejo registration page";
            };
            questions = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
              description = "Question to use for the Forgejo registration captcha";
            };
            answers = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
              description = "List of acceptable answers for the Forgejo registration captcha";
            };
          };
          served-repositories = lib.mkOption {
            type = lib.types.listOf (lib.types.submodule {
              options = {
                repo = lib.mkOption {
                  type = lib.types.str;
                  description = "Path to the repository";
                };
                rev = lib.mkOption {
                  type = lib.types.str;
                  description = "Branch, tag, or commit to serve";
                };
                subdomain = lib.mkOption {
                  type = lib.types.str;
                  default = "pages";
                  description = "Subdomain to serve the repository on";
                };
                path = lib.mkOption {
                  type = lib.types.nullOr lib.types.str;
                  default = null;
                  description = "URL prefix to serve the repository on";
                };
              };
            });
            default = [ ];
          };
        };
      };
      jellyfin = mkAppOption {
        name = "Jellyfin";
        homepage = "https://jellyfin.org";
        description = "media server";
        simpleicon = "jellyfin";
        subdomain = "media";
        port = 8096;
      };
      headscale = mkAppOption {
        name = "Headscale";
        homepage = "https://headscale.net";
        description = "mesh virtual private network";
        subdomain = "headscale";
        port = 8174;
        admin = null;
        extraOptions = {
          magicdns-subdomain = lib.mkOption {
            type = lib.types.str;
            default = "on";
            description = "Subdomain to use in the base domain for MagicDNS.";
          };
          headplane-port = lib.mkOption {
            type = lib.types.int;
            default = 8175;
            description = "Port that the headplane service listens on";
          };
          relay-port = lib.mkOption {
            type = lib.types.nullOr lib.types.int;
            default = 40108;
            description = "Port that the relay service listens on";
          };
        };
      };
      home-assistant = mkAppOption {
        name = "Home Assistant";
        homepage = "https://www.home-assistant.io";
        description = "home automation";
        simpleicon = "homeassistant";
        subdomain = "homeassistant";
        port = 8123;
        stateSubdirs = [ "state" ".storage" "blueprints" ];
      };
      homepage = mkAppOption {
        name = "Homepage";
        homepage = "https://gethomepage.dev";
        description = "personal homepage";
        service = "homepage-dashboard";
        subdomain = "home";
        port = 8082;
      };
      immich = mkAppOption {
        name = "Immich";
        homepage = "https://immich.app";
        description = "photo and video management";
        simpleicon = "immich";
        service = "immich-server";
        usesStateDir = false;
        subdomain = "photos";
        port = 2283;
      };
      llm = mkAppOption {
        name = "llama-cpp";
        homepage = "https://github.com/ggml-org/llama.cpp";
        description = "LLM inference endpoint";
        usesStateDir = false;
        subdomain = "llm";
        port = 8089;
        extraOptions = {
          local = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Whether to run a local llama-server, and serve it as an endpoint";
          };
          local-fallback = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = ''
              Whether the local endpoint should only be used when every remote
              endpoint is unhealthy, instead of participating in load balancing.
            '';
          };
          proxy = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ ];
            example = [ "workstation.lan:8089" "192.168.1.20:8089" ];
            description = ''
              Remote llama-server endpoints (as host:port) to serve alongside
              any local endpoint, subject to active health checking.
            '';
          };
          embedding = {
            enable = lib.mkOption {
              type = lib.types.bool;
              default = config.site.apps.llm.enabled;
              defaultText = lib.literalExpression "config.site.apps.llm.enabled";
              description = ''
                Whether to run a second, local llama-server dedicated to
                embeddings, serving /v1/embeddings on the same domain.
              '';
            };
            port = lib.mkOption {
              type = lib.types.int;
              default = 8088;
              description = "Port that the embedding llama-server listens on";
            };
          };
        };
      };
      ntfy = mkAppOption {
        name = "Ntfy";
        homepage = "https://ntfy.sh";
        description = "push notifications";
        simpleicon = "ntfy";
        service = "ntfy-sh";
        subdomain = "ntfy";
        port = 2586;
      };
      mealie = mkAppOption {
        name = "Mealie";
        homepage = "https://docs.mealie.io";
        description = "recipe manager";
        subdomain = "mealie";
        port = 9000;
      };
      memos = mkAppOption {
        name = "Memos";
        homepage = "https://usememos.com";
        description = "quick notes";
        subdomain = "memos";
        port = 5230;
      };
      microbin = mkAppOption {
        name = "Microbin";
        homepage = "https://github.com/szabodanika/microbin";
        description = "pastebin and url shortener";
        subdomain = "microbin";
        port = 4144;
        extraOptions = {
          title = lib.mkOption {
            type = lib.types.str;
            default = "Microbin";
            description = "Title of the Microbin app";
          };
          short-subdomain = lib.mkOption {
            type = lib.types.str;
            default = "bin";
            description = "Short subdomain for Microbin";
          };
        };
      };
      paperless = mkAppOption {
        name = "Paperless";
        homepage = "https://paperless-ngx.readthedocs.io";
        description = "document management";
        simpleicon = "paperlessngx";
        service = "paperless-web";
        subdomain = "folio";
        port = 28981;
      };
      rustical = mkAppOption {
        name = "Rustical";
        homepage = "https://rustical.app";
        description = "calendar and contacts server";
        subdomain = "cal";
        port = 4811;
      };
      scrutiny = mkAppOption {
        name = "Scrutiny";
        homepage = "https://github.com/AnalogJ/scrutiny";
        description = "disk health monitoring";
        subdomain = "drives.health";
        port = 8606;
      };
      sftpgo = mkAppOption {
        name = "SFTPGo";
        homepage = "https://sftpgo.com";
        description = "SFTP server";
        subdomain = "files";
        port = 8083;
        admin = null;
        extraOptions = {
          webdavd-port = lib.mkOption {
            type = lib.types.int;
            default = 3303;
            description = "Port that the webdavd service listens on";
          };
          sftpd-port = lib.mkOption {
            type = lib.types.int;
            default = 2022;
            description = "Port that the sftpd service listens on";
          };
        };
      };
      speedtest = mkAppOption {
        name = "Speedtest";
        homepage = "https://openspeedtest.com";
        description = "connection speed testing";
        service = "librespeed";
        usesStateDir = false;
        subdomain = "speed";
        port = 8076;
      };
      storyteller = mkAppOption {
        name = "Storyteller";
        homepage = "https://storyteller-platform.gitlab.io/storyteller/";
        description = "synced audiobook platform";
        subdomain = "books";
        port = 8001;
        cacheSubdirs = [ ".cache" ".local" "image-cache" ];
        extraOptions = {
          readium-port = lib.mkOption {
            type = lib.types.int;
            default = 8002;
            description = "Port that the Readium CLI server listens on";
          };
        };
      };
      syncthing = mkAppOption {
        name = "Syncthing";
        homepage = "https://syncthing.net";
        description = "folder synchronisation";
        simpleicon = "syncthing";
        subdomain = "syncthing";
        port = 8384;
        admin = null;
      };
      tandoor = mkAppOption {
        name = "Tandoor";
        homepage = "https://tandoor.dev";
        description = "recipe manager";
        service = "tandoor-recipes";
        subdomain = "recipes";
        port = 7203;
      };
      trek = mkAppOption {
        name = "Trek";
        homepage = "https://github.com/liketrek/TREK";
        description = "collaborative travel planner";
        subdomain = "travel";
        port = 8054;
        stateSubdirs = [ "data" "uploads" ];
      };
      transmission = mkAppOption {
        name = "Transmission";
        homepage = "https://transmissionbt.com";
        description = "torrent client";
        simpleicon = "transmission";
        subdomain = "torrent";
        port = 9092;
        stateSubdirs = [ ".config/transmission-daemon" ];
      };
      lldap = mkAppOption {
        name = "LLDAP";
        homepage = "https://github.com/lldap/lldap";
        description = "user account management";
        subdomain = "users";
        port = 17170;
      };
      uptime = mkAppOption {
        name = "Uptime Kuma";
        homepage = "https://uptime.kuma.pet";
        description = "endpoint monitoring";
        simpleicon = "uptimekuma";
        subdomain = "uptime";
        port = 3001;
      };
      vikunja = mkAppOption {
        name = "Vikunja";
        homepage = "https://vikunja.io/";
        description = "task and project management";
        subdomain = "tasks";
        port = 3456;
      };
      warracker = mkAppOption {
        name = "Warracker";
        homepage = "https://warracker.com";
        description = "warranty tracking";
        subdomain = "warracker";
        port = 8087;
      };
    };
  };

  config.assertions =
    let
      # Auxiliary listeners are found by the `*-port` suffix rather than
      # enumerated, so one added to `extraOptions` is covered without touching
      # this.
      listeners = name: app:
        lib.mapAttrsToList
          (option: port: { name = if option == "port" then name
                                  else "${name} ${lib.removeSuffix "-port" option}";
                           inherit port; })
          (lib.filterAttrs
            (option: port: (option == "port" || lib.hasSuffix "-port" option) && port != null)
            app);
      claims-here = lib.concatLists (lib.mapAttrsToList listeners
        (lib.filterAttrs (_: app: app.enabled && app.host == config.site.server.host)
          config.site.apps))
        # beszel-agent is a core module, so it listens on hosts without the hub too.
        ++ lib.optional (config.site.apps.beszel.host != config.site.server.host)
             { name = "beszel agent"; port = config.site.apps.beszel.agent-port; };
      subdomain-claims = lib.mapAttrsToList (name: app: { inherit name; inherit (app) subdomain; })
        (lib.filterAttrs (_: app: app.enabled) config.site.apps);
      clashes = field: claims:
        lib.filterAttrs (_: claimants: builtins.length claimants > 1)
          (lib.groupBy (claim: toString claim.${field}) claims);
      describe = field: contested:
        lib.concatStringsSep "; " (lib.mapAttrsToList
          (value: claimants: "${field} ${value} claimed by "
                             + lib.concatStringsSep ", " (map (c: c.name) claimants))
          contested);
      contested-ports = clashes "port" claims-here;
      contested-subdomains = clashes "subdomain" subdomain-claims;
    in [
      { assertion = contested-ports == { };
        message = "site.apps: ${describe "port" contested-ports} on ${config.site.server.host}; "
                  + "give one of them a free port in site.nix";
      }
      { assertion = contested-subdomains == { };
        message = "site.apps: ${describe "subdomain" contested-subdomains}; "
                  + "subdomains share one domain, so give one of them a distinct name in site.nix";
      }
    ];
}

{ config, lib, ... }:

let
  mkAppOption = { name, description, homepage, simpleicon ? null, subdomain, port, extraOptions ? {} }:
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
      subdomain = lib.mkOption {
        type = lib.types.str;
        default = subdomain;
        description = "Name for the ${name} app";
      };
      dir = lib.mkOption {
        type = lib.types.str;
        default = "/var/lib/${lib.toLower name}";
        description = "Directory where the ${name} app stores its data";
      };
      port = lib.mkOption {
        type = lib.types.int;
        default = port;
        description = "Port that the ${name} app listens on";
      };
      user-group = lib.mkOption {
        type = lib.types.str;
        default = lib.toLower name;
        description = "LDAP user group that has access to the ${name} app";
      };
      admin-group = lib.mkOption {
        type = lib.types.str;
        default = "admin";
        description = "User group that has admin access to the ${name} app";
      };
    } // extraOptions;
in {
  options.site = {
    domain = lib.mkOption {
      type = lib.types.str;
      default = "example.com";
      description = "Global domain for the server";
    };
    cloudflare-bypass = lib.mkOption {
      type = lib.types.str;
      default = config.site.domain;
      description = "Domain to use for bypassing Cloudflare (e.g. for SSH).";
    };
    apps = {
      authelia = mkAppOption {
        name = "Authelia";
        homepage = "https://www.authelia.com";
        description = "authentication and SSO portal";
        simpleicon = "authelia";
        subdomain = "auth";
        port = 9091;
      };
      forgejo = mkAppOption {
        name = "Forgejo";
        homepage = "https://forgejo.org";
        description = "personal software forge";
        simpleicon = "forgejo";
        subdomain = "forgejo";
        port = 3000;
      };
      headscale = mkAppOption {
        name = "Headscale";
        homepage = "https://headscale.net";
        description = "mesh virtual private network";
        simpleicon = "tailscale";
        subdomain = "headscale";
        port = 8174;
        extraOptions = {
          dns-subdomain = lib.mkOption {
            type = lib.types.str;
            default = "tails";
            description = "Base domain to use for tailnet DNS.";
          };
        };
      };
      homepage = mkAppOption {
        name = "Homepage";
        homepage = "https://gethomepage.dev";
        description = "personal homepage";
        subdomain = "home";
        port = 8082;
      };
      mealie = mkAppOption {
        name = "Mealie";
        homepage = "https://docs.mealie.io";
        description = "recipe manager";
        subdomain = "mealie";
        port = 9000;
      };
      microbin = mkAppOption {
        name = "Microbin";
        homepage = "https://github.com/szabodanika/microbin";
        description = "personal pastebin and url shortener";
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
      syncthing = mkAppOption {
        name = "Syncthing";
        homepage = "https://syncthing.net";
        description = "folder synchronisation service";
        simpleicon = "syncthing";
        subdomain = "syncthing";
        port = 8384;
      };
      lldap = mkAppOption {
        name = "LLDAP";
        homepage = "https://github.com/lldap/lldap";
        description = "user management service";
        subdomain = "lldap";
        port = 17170;
      };
      uptime = mkAppOption {
        name = "Uptime Kuma";
        homepage = "https://uptime.kuma.pet";
        description = "endpoint monitoring service";
        simpleicon = "uptimekuma";
        subdomain = "uptime";
        port = 3001;
      };
    };
  };
}
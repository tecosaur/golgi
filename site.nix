{ config, lib, ... }:

let
  mkAppOption = { name, description, subdomain, port, extraOptions ? {} }:
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
      port = lib.mkOption {
        type = lib.types.int;
        default = port;
        description = "Port that the ${name} app listens on";
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
        description = "authentication and SSO portal";
        subdomain = "auth";
        port = 9091;
      };
      forgejo = mkAppOption {
        name = "Forgejo";
        description = "personal software forge";
        subdomain = "forgejo";
        port = 3000;
      };
      headscale = mkAppOption {
        name = "Headscale";
        description = "mesh virtual private network";
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
      microbin = mkAppOption {
        name = "Microbin";
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
        description = "folder synchronisation service";
        subdomain = "syncthing";
        port = 8384;
      };
      lldap = mkAppOption {
        name = "LLDAP";
        description = "user management service";
        subdomain = "lldap";
        port = 17170;
      };
      uptime = mkAppOption {
        name = "Uptime Kuma";
        description = "endpoint monitoring service";
        subdomain = "uptime";
        port = 3001;
      };
    };
  };
}

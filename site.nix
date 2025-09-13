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
      description = "Global domain name for the site";
    };
    cloudflare-bypass-subdomain = lib.mkOption {
      type = lib.types.str;
      default = "ssh";
      description = "Domain to use for bypassing Cloudflare (e.g. for SSH).";
    };
    server = {
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
      calibre-web = mkAppOption {
        name = "Calibre web";
        homepage = "https://github.com/crocodilestick/Calibre-Web-Automated";
        description = "eBook management";
        subdomain = "ebooks";
        port = 8085;
      };
      fava = mkAppOption {
        name = "Fava";
        homepage = "https://beancount.github.io/fava/";
        description = "Beancount web interface";
        subdomain = "fava";
        port = 5025;
      };
      forgejo = mkAppOption {
        name = "Forgejo";
        homepage = "https://forgejo.org";
        description = "personal software forge";
        simpleicon = "forgejo";
        subdomain = "forgejo";
        port = 3000;
      };
      jellyfin = mkAppOption {
        name = "Jellyfin";
        homepage = "https://jellyfin.org";
        description = "media server";
        simpleicon = "jellyfin";
        subdomain = "stream";
        port = 8096;
      };
      headscale = mkAppOption {
        name = "Headscale";
        homepage = "https://headscale.net";
        description = "mesh virtual private network";
        subdomain = "headscale";
        port = 8174;
        extraOptions = {
          magicdns-subdomain = lib.mkOption {
            type = lib.types.str;
            default = "headnet";
            description = "Subdomain to use in the base domain for MagicDNS.";
          };
          headplane-port = lib.mkOption {
            type = lib.types.int;
            default = 8175;
            description = "Port that the headplane service listens on";
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
      };
      homepage = mkAppOption {
        name = "Homepage";
        homepage = "https://gethomepage.dev";
        description = "personal homepage";
        subdomain = "home";
        port = 8082;
      };
      immich = mkAppOption {
        name = "Immich";
        homepage = "https://immich.app";
        description = "photo and video management";
        simpleicon = "immich";
        subdomain = "photos";
        port = 2283;
      };
      ntfy = mkAppOption {
        name = "Ntfy";
        homepage = "https://ntfy.sh";
        description = "push notifications";
        simpleicon = "ntfy";
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
      syncthing = mkAppOption {
        name = "Syncthing";
        homepage = "https://syncthing.net";
        description = "folder synchronisation";
        simpleicon = "syncthing";
        subdomain = "syncthing";
        port = 8384;
      };
      lldap = mkAppOption {
        name = "LLDAP";
        homepage = "https://github.com/lldap/lldap";
        description = "user account management";
        subdomain = "lldap";
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
    };
  };
}

{ config, lib, pkgs, ... }:

let
  home-domain = "${config.site.apps.homepage.subdomain}.${config.site.domain}";
  search-endpoint = {
    search = "https://kagi.com/search?q=";
    suggest = "https://kagi.com/api/autosuggest?q=";
  };
  capitalizeFirst = str:
    let
      firstChar = builtins.substring 0 1 str;
      restOfString = builtins.substring 1 (builtins.stringLength str - 1) str;
    in
      lib.toUpper firstChar + restOfString;
  mkAppStatus = { title, app, icon ? null, extraOptions ? {} }:
    {
      "${title}" = ({
        href = "https://${app.subdomain}.${config.site.domain}";
        description = app.name;
        # siteMonitor = "http://localhost:${toString app.port}";
      } // (if icon != null then
        { icon = icon; }
      else if app.simpleicon != null then
        { icon = "si-${app.simpleicon}"; }
      else
        { icon = "mdi-menu-right"; }) //
      extraOptions);
    };
  mkAppLink = { app, icon ? null, extraOptions ? {} }:
    {
      "${app.name}" = [({
        href = app.homepage;
        description = capitalizeFirst app.description;
      } // (if icon != null then
        { icon = icon; }
      else if app.simpleicon != null then
        { icon = "si-${app.simpleicon}"; }
      else
        { icon = "mdi-link-variant"; }) //
      extraOptions)
      ];
    };
in {
  site.apps.homepage.enabled = true;
  services.homepage-dashboard = {
    enable = true;
    listenPort = config.site.apps.homepage.port;
    allowedHosts = "${home-domain}";
    services = [
      {
        "Storage" = [
          # (mkAppStatus {
          #   title = "Files";
          #   app = config.site.apps.sftpgo;
          #   icon = "mdi-folder-network";
          # })
          (mkAppStatus {
            title = "Syncthing";
            app = config.site.apps.syncthing;
          })
          (mkAppStatus {
            title = config.site.apps.microbin.title;
            app = config.site.apps.microbin;
            icon = "mdi-content-paste";
          })
        ];
      }
      {
        "Applications" = [
          (mkAppStatus {
            title = "Recipes";
            app = config.site.apps.mealie;
            icon = "mdi-silverware-fork-knife";
          })
          (mkAppStatus {
            title = "Todos";
            app = config.site.apps.vikunja;
            icon = "mdi-format-list-checks";
          })
          (mkAppStatus {
            title = "Notes";
            app = config.site.apps.memos;
            icon = "mdi-card-text-outline";
          })
          # (mkAppStatus {
          #   title = "Photos";
          #   app = config.site.apps.immich;
          # })
          (mkAppStatus {
            title = "Code";
            app = config.site.apps.forgejo;
          })
        ];
      }
      {
        "Server" = [
          (mkAppStatus {
            title = "Authentication";
            app = config.site.apps.authelia;
          })
          (mkAppStatus {
            title = "User Management";
            app = config.site.apps.lldap;
            icon = "mdi-account-edit";
          })
          (mkAppStatus {
            title = "Headscale";
            app = config.site.apps.headscale;
            icon = "mdi-dots-hexagon";
            extraOptions = {
              href = "https://${config.site.apps.headscale.subdomain}.${config.site.domain}/admin/";
            };
          })
          (mkAppStatus {
            title = "Notifications";
            app = config.site.apps.ntfy;
            extraOptions = {
              href = "https://${config.site.apps.ntfy.subdomain}.${config.site.domain}/app";
            };
          })
          (mkAppStatus {
            title = "Status";
            app = config.site.apps.uptime;
            extraOptions = {
              href = "https://${config.site.apps.uptime.subdomain}.${config.site.domain}/status/site";
              # widget = {
              #   type = "uptimekuma";
              #   url = "http://localhost:${toString config.site.apps.uptime.port}";
              #   slug = "site";
              # };
            };
          })
        ];
      }
    ];
    bookmarks = [
      {
        "Installed services" = ([
          (mkAppLink { app = config.site.apps.authelia; })
          {
            "Caddy" = [{
              icon = "si-caddy";
              href = "https://caddyserver.com/";
              description = "Web server";
            }];
          }
          {
            "CrowdSec" = [{
              icon = "mdi-crowd";
              href = "https://crowdsec.net";
              description = "Collaborative security";
            }];
          }
        ] ++ builtins.map mkAppLink [
          { app = config.site.apps.forgejo; }
          { app = config.site.apps.headscale;
            icon = "mdi-dots-hexagon"; }
          { app = config.site.apps.homepage;
            icon = "mdi-home-circle"; }
          { app = config.site.apps.ntfy; }
          # { app = config.site.apps.immich; }
          { app = config.site.apps.mealie;
            icon = "mdi-silverware-fork-knife";}
          { app = config.site.apps.memos;
            icon = "mdi-card-text-outline";}
          { app = config.site.apps.microbin;
            icon = "mdi-content-paste"; }
          # { app = config.site.apps.sftpgo;
          #   icon = "mdi-folder-network"; }
          { app = config.site.apps.syncthing; }
          { app = config.site.apps.lldap;
            icon = "mdi-account-edit";}
          { app = config.site.apps.uptime; }
          { app = config.site.apps.vikunja;
            icon = "mdi-format-list-checks";}
        ]);
      }
      {
        "Planned services" = [
          {
            "Immich" = [{
              icon = "si-immich";
              href = "https://immich.app";
              description = "Photo and video management";
            }];
          }
          {
            "TBD" = [{
              icon = "mdi-folder-network-outline";
              description = "File storage and sharing";
            }];
          }
          {
            "Navidrome" = [{
              icon = "mdi-playlist-music";
              href = "https://www.navidrome.org/";
              description = "Music server";
            }];
          }
        ];
      }
      {
        "Candidate services" = [
          {
            "SFTPGo" = [{
              icon = "mdi-folder-network";
              href = "https://sftpgo.com";
              description = "File storage and sharing (1)";
            }];
          }
          {
            "ownCloud" = [{
              icon = "si-owncloud";
              href = "https://owncloud.com/infinite-scale";
              description = "File storage and sharing (2)";
            }];
          }
          {
            "Paperless-ngx" = [{
              icon = "si-paperlessngx";
              href = "https://paperless-ngx.com";
              description = "Document management";
            }];
          }
          {
            "Home Assistant" = [{
              icon = "si-homeassistant";
              href = "https://www.home-assistant.io";
              description = "Smart automation";
            }];
          }
          {
            "Jellyfin" = [{
              icon = "si-jellyfin";
              href = "https://jellyfin.org";
              description = "Media server";
            }];
          }
          {
            "Feishin" = [{
              icon = "mdi-music";
              href = "https://github.com/jeffvli/feishin";
              description = "Music player";
            }];
          }
        ];
      }
      {
        "Server management" = [
          {
            "Hetzner" = [{
              icon = "si-hetzner";
              href = "https://console.hetzner.cloud";
              description = "VPS hosting";
            }];
          }
          {
            "Cloudflare" = [{
              icon = "si-cloudflare";
              href = "https://dash.cloudflare.com";
              description = "DNS and CDN";
            }];
          }
          {
            "Porkbun" = [{
              icon = "si-porkbun";
              href = "https://porkbun.com/account";
              description = "Domain registrar";
            }];
          }
          {
            "System" = [{
              icon = "si-nixos";
              href = "https://code.tecosaur.net/tec/golgi";
              description = "Server configuration";
            }];
          }
          {
            "Uptime" = [{
              icon = "mdi-circle-slice-8";
              href = "https://stats.uptimerobot.com/ah8wBH3PYy";
              description = "Server monitoring";
            }];
          }
        ];
      }
    ];
    widgets = [
      {
        search = {
          provider = "custom";
          url = search-endpoint.search;
          suggestionUrl = search-endpoint.suggest;
          showSearchSuggestions = true;
          target = "_blank";
        };
      }
      {
        resources = {
          cpu = true;
          memory = true;
          # disk = "/";
        };
      }
    ];
    settings = {
      title = "Home";
      favicon = "https://${config.site.domain}/favicon.ico";
      hideVersion = true;
      statusStyle = "dot";
      headerStyle = "clean";
      # layout = {
      #   "Storage" = {
      #     icon = "mdi-database";
      #   };
      #   "Development" = {
      #     icon = "mdi-xml";
      #   };
      #   "Server" = {
      #     icon = "mdi-nas";
      #   };
      # };
    };
  };

  services.caddy.virtualHosts."${home-domain}".extraConfig =
    ''
    import auth
    reverse_proxy :${toString config.site.apps.homepage.port}
    '';
}

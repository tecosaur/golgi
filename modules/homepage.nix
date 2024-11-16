{ config, lib, pkgs, ... }:

let
  home-domain = "${config.site.apps.homepage.subdomain}.${config.site.domain}";
  search-endpoint = {
    search = "https://kagi.com/search?q=";
    suggest = "https://kagi.com/api/autosuggest?q=";
  };
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
    services = [
      {
        "Storage" = [
          (mkAppStatus {
            title = "Files";
            app = config.site.apps.sftpgo;
            icon = "mdi-folder-network";
          })
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
    bookmarks = [{
      "Service documentation" = builtins.map mkAppLink [
        { app = config.site.apps.authelia; }
        { app = config.site.apps.forgejo; }
        { app = config.site.apps.headscale; }
        { app = config.site.apps.mealie;
          icon = "mdi-silverware-fork-knife";}
        { app = config.site.apps.microbin;
          icon = "mdi-content-paste"; }
        { app = config.site.apps.syncthing; }
        { app = config.site.apps.lldap;
          icon = "mdi-account-edit";}
        { app = config.site.apps.uptime; }
      ];
    }
    {
      "Server management" = [
        {
          "Hetzner" = [{
            icon = "si-hetzner";
            href = "https://console.hetzner.cloud";
          }];
        }
        {
          "Cloudflare" = [{
            icon = "si-cloudflare";
            href = "https://dash.cloudflare.com";
          }];
        }
        {
          "Porkbun" = [{
            icon = "si-porkbun";
            href = "https://porkbun.com/account";
          }];
        }
        {
          "Uptime" = [{
            icon = "mdi-circle-slice-8";
            href = "https://stats.uptimerobot.com/ah8wBH3PYy";
          }];
        }
      ];
    }];
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
    reverse_proxy :${toString config.services.homepage-dashboard.listenPort}
    '';
}

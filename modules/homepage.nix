{ config, lib, pkgs, ... }:

let
  home-domain = "${config.site.apps.homepage.subdomain}.${config.site.domain}";
  search-endpoint = {
    search = "https://kagi.com/search?q=";
    suggest = "https://kagi.com/api/autosuggest?q=";
  };
  mkAppStatus = { title, app, icon, extraOptions ? {} }:
    {
      "${title}" = {
        href = "https://${app.subdomain}.${config.site.domain}";
        icon = icon;
        description = app.name;
        # siteMonitor = "http://localhost:${toString app.port}";
      } // extraOptions;
    };
in {
  site.apps.homepage.enabled = true;
  services.homepage-dashboard = {
    enable = true;
    services = [
      {
        "Storage" = [
          (mkAppStatus {
            title = "Syncthing";
            icon = "si-syncthing";
            app = config.site.apps.syncthing;
          })
          (mkAppStatus {
            title = config.site.apps.microbin.title;
            icon = "mdi-content-paste";
            app = config.site.apps.microbin;
          })
        ];
      }
      {
        "Applications" = [
          (mkAppStatus {
            title = "Recipies";
            icon = "mdi-silverware-fork-knife";
            app = config.site.apps.mealie;
          })
          (mkAppStatus {
            title = "Code";
            icon = "si-forgejo";
            app = config.site.apps.forgejo;
          })
        ];
      }
      {
        "Server" = [
          (mkAppStatus {
            title = "Authentication";
            icon = "si-authelia";
            app = config.site.apps.authelia;
          })
          (mkAppStatus {
            title = "User Management";
            icon = "mdi-account-edit";
            app = config.site.apps.lldap;
          })
          (mkAppStatus {
            title = "Status";
            icon = "si-uptimekuma";
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
{ config, lib, pkgs, ... }:

let
  paste-domain = "pastes.${config.globals.domain}";
  page-name = "μPaste";
in
let
  caddy-unauth-filter =
    ''
    @unauth-html {
        not header Cookie *authelia_session*
        path /upload/* /p/*
    }
    replace @unauth-html {
        re "<div id=\"nav\"[\s\S]*?</div>[\s\S]*?" ""
        re `<div style="float: left">\s*(?:(<button[^>]*>[\s\S]+?<\/button>(?:\s*<button[^>]*>[^>]+?<\/button>)?)\s*(<a[^>]+>Raw)[^<]+(<\/a>))?[\s\S]*?<\/div>` <<HTML
          <div style="float: left">
          <b style="margin-right: 1.5rem">
            <a href="https://${paste-domain}">
              <img width=100 style="margin-bottom: -6px; margin-right: 0.5rem;" src="https://${paste-domain}/static/logo.png"
                  onload="this.parentElement.href = 'https://${config.globals.auth-domain}/?rd=' + encodeURIComponent(window.location.href) + '&rm=GET';">
            </a>
            ${config.services.microbin.settings.MICROBIN_TITLE}
          </b>
          $1$2$3
          </div>
          HTML
        re "\n*<div>\s*<p[^>]*>Read[^<]+<\/p>\s*<\/div>" ""
        `<a href="https://${paste-domain}/"> Go Home</a>` ""
    }
    '';
  caddy-settings-filter =
    ''
    replace / {
        "﹖" "?"
        re `<br>\s*<div id="settings">` <<HTML
          <details>
            <summary style="padding: 4px 10px;">Settings</summary>
            <div id="settings">
            $1
        HTML
        re `</div>\s*<label>Content</label>` <<HTML
            </div>
          </details>
          <label>Content</label>
        HTML
    }
    '';
  caddy-nav-filter =
    ''
    @nav_page path / /list /guide /admin /auth_admin /upload/* /p/* /qr/*
    replace @nav_page {
        re `<div id="nav" style="margin-bottom: 1rem;">\s*(<b[\S\s]+?<\/b>)\s*([\S\s]+?)<\/div>` <<HTML
          <div id="nav" style="margin-bottom: 1rem; float: left;">
            $1
          </div>
          <div style="float: right;">
            $2
          </div>
          <br>
        HTML
    }
    '';
in {
  services.microbin = {
    enable = true;
    settings = {
      MICROBIN_ADMIN_PASSWORD = ""; # Security through Authelia
      MICROBIN_DATA_DIR = "data"; # It's under /var/lib/microbin anyway
      MICROBIN_DISABLE_UPDATE_CHECKING = true;
      MICROBIN_EDITABLE = true;
      MICROBIN_ENABLE_BURN_AFTER = true;
      MICROBIN_ENABLE_READONLY = true;
      MICROBIN_ENCRYPTION_CLIENT_SIDE = true;
      MICROBIN_ENCRYPTION_SERVER_SIDE = true;
      MICROBIN_ETERNAL_PASTA = true;
      MICROBIN_GC_DAYS = 0;
      MICROBIN_HIDE_FOOTER = true;
      MICROBIN_HIGHLIGHTSYNTAX = true;
      MICROBIN_PORT = 4144;
      MICROBIN_PRIVATE = false; # They're all essentially private
      MICROBIN_PUBLIC_PATH = "https://${paste-domain}";
      MICROBIN_QR = true;
      MICROBIN_SHOW_READ_STATS = true;
      MICROBIN_TITLE = "${page-name}";
    };
  };

  services.caddy.virtualHosts."${paste-domain}".extraConfig =
    ''
    @public path /static/* /upload/* /file/* /p/* /raw/* /u/* /qr/* /auth/* /auth_file/*
    route @public {
        ${caddy-unauth-filter}
        reverse_proxy :${toString config.services.microbin.settings.MICROBIN_PORT} {
            header_up Accept-Encoding identity
        }
    }
    route * {
        import auth
        ${caddy-settings-filter}
        ${caddy-nav-filter}
        reverse_proxy :${toString config.services.microbin.settings.MICROBIN_PORT} {
            header_up Accept-Encoding identity
        }
    }
    '';

  services.authelia.instances.main.settings.access_control.rules = [
    {
      domain = paste-domain;
      policy = "one_factor";
      subject = "group:paste";
    }
    {
      domain = paste-domain;
      policy = "deny";
    }
  ];
}
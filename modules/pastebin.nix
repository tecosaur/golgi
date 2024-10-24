{ config, lib, pkgs, ... }:

let
  paste-domain = "pastes.${config.globals.domain}";
  page-name = "μPaste";
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
    @public path /upload/* /raw/* /u/* /qr/* /static/*
    route @public {
        reverse_proxy :${toString config.services.microbin.settings.MICROBIN_PORT}
    }
    route * {
        import auth
        reverse_proxy :${toString config.services.microbin.settings.MICROBIN_PORT}
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

{ config, lib, pkgs, ... }:

let
  cwa-package = (pkgs.callPackage ../packages/calibre-web-automated.nix { }).overridePythonAttrs (old: {
    dependencies = old.dependencies ++
                   old.optional-dependencies.metadata ++
                   old.optional-dependencies.oauth;
  });
  cwa-runtime-deps = with pkgs; [
    calibre               # calibredb, ebook-convert
    kepubify              # kepub converter (optional but common)
    unar                  # archive handling; use unrar if you prefer non-free
    p7zip
    imagemagick
    ffmpegthumbnailer
    file                  # libmagic CLI
    shared-mime-info
    xdg-utils
    sqlite
    lsof
  ];
  cwa-state-dir = "/var/lib/calibre-web";
  cwa-data-dir = "/data/media/books";
in {
  site.apps.calibre-web.enabled = true;

  systemd.services.calibre-web = {
    description = "Calibre-Web eBook management web app";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];
    path = cwa-runtime-deps;
    environment = {
      CACHE_DIR = "/var/cache/calibre-web";
      CALIBRE_DBPATH = "config";
      CWA_PORT_OVERRIDE = toString config.site.apps.calibre-web.port;
      LOCALE_ARCHIVE = "${pkgs.glibcLocales}/lib/locale/locale-archive";
      FONTCONFIG_PATH = "${pkgs.fontconfig.out}/etc/fonts";
      FLASK_DEBUG = "1";
    };
    serviceConfig = {
      Type = "simple";
      User = "calibre-web";
      Group = "users";
      WorkingDirectory = cwa-state-dir;
      CacheDirectory = "calibre-web";
      CacheDirectoryMode = "0755";
      ExecStart = "${lib.getExe cwa-package} -g '${cwa-state-dir}/gdrive.db' -i '127.0.0.1'";
      ExecStartPre = pkgs.writeShellScript "cwa-setup" ''
      mkdir -p config/{processed_books/{converted,failed,imported,fixed_originals},metadata_temp,metadata_change_logs}
      ln -sf '${cwa-data-dir}' calibre-library
      ${cwa-package}/bin/auto_library
      sqlite3 config/app.db <<EOF
          update settings set config_kepubifypath='${pkgs.kepubify}/bin/kepublify', config_converterpath='${pkgs.calibre}/bin/ebook-convert', config_binariesdir='${pkgs.calibre}/bin', config_rarfile_location='${pkgs.unar}/bin/unar';
      EOF
      if [ ! -f config/user_profiles.json ]; then
        echo "{}" > config/user_profiles.json
      fi
      '';
      Restart = "on-failure";
    };
  };

  users.users.calibre-web = {
    isSystemUser = true;
    home = cwa-state-dir;
    createHome = true;
    description = "Calibre-Web user";
    group = "calibre-web";
    extraGroups = [ "users" ];
  };

  users.groups.calibre-web = { };

  systemd.tmpfiles.rules = [
    "d ${cwa-data-dir} 0755 calibre-web users - -"
  ];

  services.caddy.virtualHosts."${config.site.apps.calibre-web.subdomain}.${config.site.domain}".extraConfig =
    ''
    reverse_proxy :${toString config.site.apps.calibre-web.port}
    '';
}

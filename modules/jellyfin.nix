{ config, lib, pkgs, ... }:

# Look at: <https://github.com/Sveske-Juice/declarative-jellyfin>
# Also see: <https://github.com/9p4/jellyfin-plugin-sso/issues/16#issuecomment-2953811762>

let
  media-dir = "/data/media";
  movies-dir = "${media-dir}/movies";
  shows-dir = "${media-dir}/shows";
  books-dir = "${media-dir}/books";
  music-dir = "${media-dir}/music";
  jellyfin-domain = "${config.site.apps.jellyfin.subdomain}.${config.site.domain}";
in {
  site.apps.jellyfin.enabled = true;

  services.declarative-jellyfin = {
    enable = true;
    serverId = "0mdg8vydu0b46asdj6r28hdwkh2bi7zj";
    network = {
      enableIPv6 = true;
      enableHttps = false; # Handled by Caddy
      internalHttpPort = config.site.apps.jellyfin.port;
      publicHttpPort = config.site.apps.jellyfin.port;
      publishedServerUriBySubnet = [ "all=https://${jellyfin-domain}" ];
    };
    encoding = {
      enableHardwareEncoding = true;
      hardwareAccelerationType = "vaapi";
      enableDecodingColorDepth10Hevc = true;
      allowHevcEncoding = true;
      allowAv1Encoding = true;
      hardwareDecodingCodecs = [
        "h264"
        "hevc"
        "mpeg2video"
        "vc1"
        "vp9"
        "vp8"
        "av1"
      ];
    };
    system = {
      trickplayOptions = {
        enableHwAcceleration = true;
        enableHwEncoding = true;
        enableKeyFrameOnlyExtraction = true;
        processThreads = 2;
      };
    };
    libraries = {
      Movies = {
        enabled = true;
        contentType = "movies";
        pathInfos = [ movies-dir ];
        typeOptions.Movies = {
          metadataFetchers = [
            "The Open Movie Database"
            "TheMovieDb"
          ];
          imageFetchers = [
            "The Open Movie Database"
            "TheMovieDb"
          ];
        };
      };
      Shows = {
        enabled = true;
        contentType = "tvshows";
        pathInfos = [ shows-dir ];
      };
      Books = {
        enabled = true;
        contentType = "books";
        pathInfos = [ books-dir ];
      };
      Music = {
        enabled = true;
        contentType = "music";
        pathInfos = [ music-dir ];
      };
    };
    users = {
      admin = {
        mutable = false;
        hashedPassword = "$PBKDF2-SHA512$iterations=210000$EBADD66838EB56B9C6A7E475DF14548A$AB58132A66852B837ADE581C99964B7DEC9842DC7920933E06D3F18A7E41527B2C224F361DC490F5EBC35D83A9E31DA234F33FBBC9E7FBA122260982C28E888F";
        permissions = {
          isAdministrator = true;
        };
      };
    };
  };

  users.users.${config.services.jellyfin.user}.extraGroups = ["video" "render"];

  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [
      vaapiVdpau
      libvdpau-va-gl
    ];
  };

  systemd.tmpfiles.rules = [
    "d ${media-dir} 0755 root users - -"
    "d ${movies-dir} 0775 ${config.services.jellyfin.user} users - -"
    "d ${shows-dir} 0775 ${config.services.jellyfin.user} users - -"
    "d ${books-dir} 0575 ${config.services.jellyfin.user} users - -"
    "d ${music-dir} 0575 ${config.services.jellyfin.user} users - -"
  ];

  services.caddy.virtualHosts."${config.site.apps.jellyfin.subdomain}.${config.site.domain}".extraConfig =
    ''
    handle /web/assets/img/icon-transparent.png {
        uri strip_prefix /web/assets/img
        root * ${../assets/jellyfin}
        file_server
    }
    handle /web/*.ico {
        rewrite * /jellyfin.ico
        root * ${../assets/jellyfin}
        file_server
    }
    reverse_proxy :${toString config.site.apps.jellyfin.port}
    '';
}

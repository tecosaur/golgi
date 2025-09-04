{ config, lib, pkgs, ... }:

# Look at: <https://github.com/Sveske-Juice/declarative-jellyfin>
# Also see: <https://github.com/9p4/jellyfin-plugin-sso/issues/16#issuecomment-2953811762>

# Then also (https://gitlab.com/DomiStyle/jellysearch):
# - <https://git.vimium.com/jordan/nix-config/src/branch/master/pkgs/jellysearch>
# - <https://git.vimium.com/jordan/nix-config/src/branch/master/hosts/library/jellysearch.nix>

let
  media-dir = "/data/media";
  movies-dir = "${media-dir}/movies";
  shows-dir = "${media-dir}/shows";
  anime-dir = "${media-dir}/anime";
  books-dir = "${media-dir}/books";
  music-dir = "${media-dir}/music";
  jellyfin-domain = "${config.site.apps.jellyfin.subdomain}.${config.site.domain}";
in {
  site.apps.jellyfin.enabled = true;

  age.secrets.jellyfin-oidc = {
    owner = "jellyfin";
    group = "users";
    file = ../../secrets/jellyfin-oidc-secret.age;
  };

  services.declarative-jellyfin = {
    enable = true;
    serverId = "f2d18e8c67994ce1baa11016df427c9f";
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
      serverName = "Media";
      trickplayOptions = {
        enableHwAcceleration = true;
        enableHwEncoding = true;
        enableKeyFrameOnlyExtraction = true;
        processThreads = 2;
      };
      pluginRepositories = [
        {
          tag = "RepositoryInfo";
          content = {
            Name = "Jellyfin Stable";
            Url = "https://repo.jellyfin.org/files/plugin/manifest.json";
          };
        }
      ];
    };
    libraries = {
      Movies = {
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
        contentType = "tvshows";
        pathInfos = [ shows-dir ];
        enableAutomaticSeriesGrouping = true;
      };
      Anime = {
        contentType = "tvshows";
        pathInfos = [ anime-dir ];
        enableAutomaticSeriesGrouping = true;
      };
      Books = {
        contentType = "books";
        pathInfos = [ books-dir ];
      };
      Music = {
        contentType = "music";
        pathInfos = [ music-dir ];
        customTagDelimiters = [ "," "/" "|" ";" ];
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

  # Declarative Jellyfin replaces the `ExecStart` of the `jellyfin`
  # service with a wrapper script, which means we can safely claim
  # `preStart` ourselves.
  systemd.services.jellyfin.preStart = let
    branding-xml =
      ''
      <?xml version="1.0" encoding="utf-8"?>
      <BrandingOptions xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema">
        <LoginDisclaimer>&lt;form action="https://${jellyfin-domain}/sso/OID/start/authelia"&gt;
        &lt;button class="raised block emby-button button-submit"&gt;
          Sign in
        &lt;/button&gt;
      &lt;/form&gt;</LoginDisclaimer>
        <CustomCss>${builtins.replaceStrings [ "&" "<" ">" ] [ "&amp;" "&lt;" "&gt;" ]
          (lib.trim (builtins.readFile ./jellyfin.css))}</CustomCss>
        <SplashscreenEnabled>false</SplashscreenEnabled>
      </BrandingOptions>
      '';
    branding-file = pkgs.writeText "jellyfin-branding.xml" branding-xml;
    branding-path = "${config.services.jellyfin.configDir}/branding.xml";
    sso-template = builtins.replaceStrings [ "#oidc_endpoint#" ]
      [ "https://${config.site.apps.authelia.subdomain}.${config.site.domain}" ]
      (builtins.readFile ./jellyfin-sso-template.xml);
    sso-file = pkgs.writeText "jellyfin-sso.xml" sso-template;
    sso-path = "${config.services.jellyfin.dataDir}/plugins/configurations/SSO-Auth.xml";
    replaceSecretBin = lib.getExe pkgs.replace-secret;
    xmlstarlet = lib.getExe pkgs.xmlstarlet;
  in
    ''
    umask 007
    mkdir -p "$(dirname '${branding-path}')"
    cp -rf '${branding-file}' '${branding-path}'
    mkdir -p '${config.services.jellyfin.configDir}/plugins/configurations'
    # Preserve folder settings that cannot (easily) be managed declaratively
    if [ -f '${sso-path}' ]; then
        JELLY_OIDC_ENABLED_FOLDERS="$(${xmlstarlet} sel -t -c '//PluginConfiguration/OidConfigs[1]/item/value/PluginConfiguration/EnabledFolders' '${sso-path}' | sed '1d;$d')"
        JELLY_OIDC_FOLDER_ROLE_MAPPINGS="$(${xmlstarlet} sel -t -c '//PluginConfiguration/OidConfigs[1]/item/value/PluginConfiguration/FolderRoleMappings' '${sso-path}' | sed '1d;$d')"
    else
        JELLY_OIDC_ENABLED_FOLDERS=""
        JELLY_OIDC_FOLDER_ROLE_MAPPINGS=""
    fi
    mkdir -p "$(dirname '${sso-path}')"
    install -m 600 '${sso-file}' '${sso-path}'
    ${replaceSecretBin} '#oidc_secret#' '${config.age.secrets.jellyfin-oidc.path}' '${sso-path}'
    sed -i '/#enabled_folders#/{
      r /dev/stdin
      d
    }' '${sso-path}' <<<"$JELLY_OIDC_ENABLED_FOLDERS"
    sed -i '/#folder_role_mappings#/{
      r /dev/stdin
      d
    }' '${sso-path}' <<<"$JELLY_OIDC_FOLDER_ROLE_MAPPINGS"
    '';

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
    "d ${anime-dir} 0775 ${config.services.jellyfin.user} users - -"
    # "d ${books-dir} 0575 ${config.services.jellyfin.user} users - -"
    "d ${music-dir} 0575 ${config.services.jellyfin.user} users - -"
  ];

  services.caddy.virtualHosts."${config.site.apps.jellyfin.subdomain}.${config.site.domain}".extraConfig =
    ''
    handle_path /web/assets/img/* {
        root * ${../../assets/jellyfin}
        try_files {path} {http.request.uri}
        file_server
    }
    handle /web/*.ico {
        rewrite * /jellyfin.ico
        root * ${../../assets/jellyfin}
        file_server
    }
    reverse_proxy :${toString config.site.apps.jellyfin.port}
    '';
}

{ config, lib, pkgs, ... }:

# multi-scrobbler collects from Deezer, Jellyfin and Lyrion into Koito, and
# relays them on to ListenBrainz for its recommendations.
#
# Players that speak ListenBrainz (Lyrion's AudioScrobbler plugin, rescrobbled
# on a desktop) are pointed at https://<scrobbler domain>/1/ with the endpoint
# token by hand. The /1/ and trailing slash matter: clients append bare
# endpoint names to the URL.

let
  koito = config.site.apps.koito;
  koito-env = "/run/koito/env";
  koito-user = "admin";
  site-theme = "site";
  icons-version = lib.substring 0 8 (baseNameOf "${config.site.assets}");
  scrobbler = config.site.apps.multi-scrobbler;
  scrobbler-domain = "${scrobbler.subdomain}.${config.site.domain}";
  scrobbler-secrets-env = "/run/multi-scrobbler/secrets.env";
  # A browser cookie only the user can supply, so it does not block a deploy.
  has-deezer-arl = builtins.pathExists ../secrets/credentials/deezer-arl.age;
  # Likewise a user token from listenbrainz.org.
  has-listenbrainz-token = builtins.pathExists ../secrets/credentials/listenbrainz-token.age;
  jellyfin = config.site.apps.jellyfin;
in {
  site.apps.koito.enabled = true;
  site.apps.multi-scrobbler.enabled = true;

  assertions = [
    { assertion = scrobbler.jellyfin-user != null;
      message = "scrobbler: site.apps.multi-scrobbler.jellyfin-user names the Jellyfin account to scrobble for";
    }
    { assertion = has-listenbrainz-token -> scrobbler.listenbrainz-user != null;
      message = "scrobbler: secrets/credentials/listenbrainz-token.age exists, so site.apps.multi-scrobbler.listenbrainz-user must name its account";
    }
  ];

  age.secrets = {
    koito-admin-password = {
      owner = "koito";
      file = ../secrets/passwords/koito-admin-password.age;
    };
    multi-scrobbler-endpoint-token = {
      owner = "multi-scrobbler";
      file = ../secrets/passwords/multi-scrobbler-endpoint-token.age;
    };
    multi-scrobbler-koito = {
      owner = "koito";
      group = "multi-scrobbler";
      mode = "0440";
      file = ../secrets/keys/multi-scrobbler-koito.age;
    };
    multi-scrobbler-jellyfin = {
      owner = "multi-scrobbler";
      file = ../secrets/keys/multi-scrobbler-jellyfin.age;
    };
    deezer-arl = lib.mkIf has-deezer-arl {
      owner = "multi-scrobbler";
      file = ../secrets/credentials/deezer-arl.age;
    };
    listenbrainz-token = lib.mkIf has-listenbrainz-token {
      owner = "multi-scrobbler";
      file = ../secrets/credentials/listenbrainz-token.age;
    };
  };

  services.koito = {
    enable = true;
    # Titles are strung together inside the client, and it serves its chunks and
    # icons as immutable for a year, so the source is patched and rebuilt: the
    # chunk hashes then move with the title, and the icon URLs carry a version.
    package = pkgs.koito.overrideAttrs (old: {
      passthru = old.passthru // {
        client = old.passthru.client.overrideAttrs (client: {
          postPatch = (client.postPatch or "") + ''
            cp ${config.site.assets}/koito/{favicon.svg,favicon.ico,favicon-96x96.png,apple-touch-icon.png,web-app-manifest-192x192.png,web-app-manifest-512x512.png} public/
            sed -Ei 's#href="/(favicon[^"]*|apple-touch-icon\.png)"#href="/\1?v=${icons-version}"#' app/root.tsx
            sed -Ei 's#"src": "/(web-app-manifest[^"]*)"#"src": "/\1?v=${icons-version}"#' public/site.webmanifest
            substituteInPlace app/root.tsx \
              --replace-fail 'content="Koito"' 'content="${koito.title}"' \
              --replace-fail '- Koito`' '- ${koito.title}`'
            substituteInPlace app/routes/Home.tsx public/site.webmanifest \
              --replace-fail '"Koito"' '"${koito.title}"'
            substituteInPlace app/routes/Charts/ChartLayout.tsx \
              app/routes/MediaItems/MediaLayout.tsx app/routes/RewindPage.tsx \
              --replace-fail '- Koito`' '- ${koito.title}`'
            # Varia's neutrals around the site accents. The dims are never rendered.
            substituteInPlace app/styles/themes.css.ts \
              --replace-fail 'export const themes: Record<string, Theme> = {' \
              'export const themes: Record<string, Theme> = {
              ${site-theme}: {
                bg: "#19191d", bgSecondary: "#1D1D24", bgTertiary: "#343442",
                fg: "#edeef2", fgSecondary: "#a8a8b4", fgTertiary: "#848492",
                primary: "${config.site.accent.primary}",
                primaryDim: "color-mix(in srgb, ${config.site.accent.primary} 80%, black)",
                accent: "${config.site.accent.secondary}",
                accentDim: "color-mix(in srgb, ${config.site.accent.secondary} 80%, black)",
                error: "#F06767", warning: "#f07828", success: "#48b058", info: "#4090e8",
              },'
          '';
        });
      };
    });
    environment = {
      KOITO_BIND_ADDR = "127.0.0.1";
      KOITO_LISTEN_PORT = koito.port;
      KOITO_CONFIG_DIR = koito.dir;
      KOITO_DEFAULT_USERNAME = koito-user;
      KOITO_LOGIN_GATE = "false";
      KOITO_DEFAULT_THEME = site-theme;
    };
  };

  systemd.services.koito = {
    path = [ pkgs.curl pkgs.sqlite ];
    preStart = ''
      umask 077
      echo "KOITO_DEFAULT_PASSWORD=$(cat ${config.age.secrets.koito-admin-password.path})" \
        > ${koito-env}
    '';
    # Koito makes the database and user on first run, so the key goes in after.
    # Keys are stored plain; the secret is alphanumeric, so safe in the literal.
    postStart = ''
      for _ in $(seq 60); do
        curl -sf -o /dev/null http://127.0.0.1:${toString koito.port}/apis/web/v1/health && break
        sleep 1
      done
      [ -e ${koito.dir}/koito.db ] || {
        echo "koito: not ready after 60s; multi-scrobbler's key not installed" >&2
        exit 0
      }
      token="$(cat ${config.age.secrets.multi-scrobbler-koito.path})"
      installed="$(sqlite3 -cmd '.timeout 10000' ${koito.dir}/koito.db \
        "DELETE FROM api_keys WHERE label = 'multi-scrobbler' AND key != '$token';
         INSERT OR IGNORE INTO api_keys (key, user_id, created_at, label)
           SELECT '$token', id, unixepoch(), 'multi-scrobbler'
           FROM users WHERE username = '${koito-user}';
         SELECT count(*) FROM api_keys WHERE key = '$token';")"
      [ "$installed" = 1 ] ||
        echo "koito: no user '${koito-user}', so multi-scrobbler's key not installed" >&2
    '';
    serviceConfig = {
      # Static user, so data-mounts binds the state directory.
      DynamicUser = lib.mkForce false;
      User = "koito";
      Group = "koito";
      RuntimeDirectory = "koito";
      RuntimeDirectoryMode = "0700";
      # Written by preStart; the module's own default is null.
      EnvironmentFile = lib.mkForce "-${koito-env}";
    };
  };

  systemd.services.multi-scrobbler = {
    description = "multi-scrobbler scrobble collector";
    after = [ "network-online.target" "koito.service" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    environment = {
      CONFIG_DIR = scrobbler.dir;
      # Defaults under $HOME.
      DATA_DIR = scrobbler.dir;
      PORT = toString scrobbler.port;
      BASE_URL = "https://${scrobbler-domain}";
      TZ = config.time.timeZone;
    };
    # [[NAME]] is filled from the environment; SECRET_ keeps clear of
    # multi-scrobbler's own ENV-config keys (DEEZER_ARL, JELLYFIN_APIKEY, ...).
    preStart = ''
      install -m 0600 ${pkgs.writeText "multi-scrobbler-config.json" (builtins.toJSON {
        sources = lib.warnIf (!has-deezer-arl)
          "scrobbler: no (tracked) secrets/credentials/deezer-arl.age, so no Deezer source"
          (lib.optional has-deezer-arl
            { type = "deezer"; id = "deezer"; name = "Deezer";
              data.arl = "[[SECRET_DEEZER_ARL]]"; }
          ++ [
            { type = "jellyfin"; id = "jellyfin"; name = "Jellyfin";
              data = {
                url = if jellyfin.host == config.site.server.host
                  then "http://127.0.0.1:${toString jellyfin.port}"
                  else "https://${jellyfin.subdomain}.${config.site.domain}";
                user = scrobbler.jellyfin-user;
                apiKey = "[[SECRET_JELLYFIN_KEY]]";
                frontendUrlOverride = "https://${jellyfin.subdomain}.${config.site.domain}";
              }; }
            { type = "endpointlz"; id = "endpoint"; name = "ListenBrainz endpoint";
              data.token = "[[SECRET_ENDPOINT_TOKEN]]"; }
          ]);
        # Sources scrobble to every client unless told otherwise.
        clients = [
          { type = "koito"; id = "koito"; name = "Koito";
            data = {
              url = "http://127.0.0.1:${toString koito.port}";
              username = koito-user;
              token = "[[SECRET_KOITO_KEY]]";
            }; }
        ] ++ lib.optional has-listenbrainz-token
          { type = "listenbrainz"; id = "listenbrainz"; name = "ListenBrainz";
            data = {
              username = scrobbler.listenbrainz-user;
              token = "[[SECRET_LISTENBRAINZ_TOKEN]]";
            }; };
      })} ${scrobbler.dir}/config.json
      umask 077
      { echo "SECRET_JELLYFIN_KEY=$(cat ${config.age.secrets.multi-scrobbler-jellyfin.path})"
        echo "SECRET_ENDPOINT_TOKEN=$(cat ${config.age.secrets.multi-scrobbler-endpoint-token.path})"
        echo "SECRET_KOITO_KEY=$(cat ${config.age.secrets.multi-scrobbler-koito.path})"
        ${lib.optionalString has-deezer-arl
          ''echo "SECRET_DEEZER_ARL=$(cat ${config.age.secrets.deezer-arl.path})"''}
        ${lib.optionalString has-listenbrainz-token
          ''echo "SECRET_LISTENBRAINZ_TOKEN=$(cat ${config.age.secrets.listenbrainz-token.path})"''}
      } > ${scrobbler-secrets-env}
    '';
    serviceConfig = {
      User = "multi-scrobbler";
      Group = "multi-scrobbler";
      ExecStart = lib.getExe pkgs.multi-scrobbler;
      Restart = "on-failure";
      RestartSec = 10;
      StateDirectory = "multi-scrobbler";
      RuntimeDirectory = "multi-scrobbler";
      RuntimeDirectoryMode = "0700";
      EnvironmentFile = "-${scrobbler-secrets-env}";
      # Hardening
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      PrivateDevices = true;
      ProtectControlGroups = true;
      ProtectKernelTunables = true;
      ProtectKernelModules = true;
      ProtectKernelLogs = true;
      ProtectClock = true;
      ProtectHostname = true;
      LockPersonality = true;
      RestrictRealtime = true;
      RestrictNamespaces = true;
      RestrictSUIDSGID = true;
      RestrictAddressFamilies = [ "AF_INET" "AF_INET6" "AF_UNIX" ];
      CapabilityBoundingSet = [ "" ];
      UMask = "0077";
    };
  };

  users.users.koito = { isSystemUser = true; group = "koito"; };
  users.groups.koito = { };
  users.users.multi-scrobbler = { isSystemUser = true; group = "multi-scrobbler"; };
  users.groups.multi-scrobbler = { };

  services.caddy.virtualHosts = {
    # Public, like a ListenBrainz profile; Koito's own login guards editing.
    "${koito.subdomain}.${config.site.domain}".extraConfig = ''
      reverse_proxy :${toString koito.port}
    '';
    # Token-checked; the rest of /1/ (playing-now) is not.
    ${scrobbler-domain}.extraConfig = ''
      @endpoint path /1/submit-listens /1/validate-token
      route @endpoint {
        reverse_proxy :${toString scrobbler.port}
      }
      route {
        import auth
        reverse_proxy :${toString scrobbler.port}
      }
    '';
  };
}

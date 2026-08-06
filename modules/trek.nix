{ config, lib, pkgs, ... }:

let
  trek = config.site.apps.trek;
  trek-domain = "${trek.subdomain}.${config.site.domain}";
  trek-pkg = pkgs.callPackage ../packages/trek.nix { };
  # A tree of links to the package: the server writes beside its own location.
  trek-runtime = "/var/lib/trek/runtime";
  trek-plugins-dir = "${trek-runtime}/server/data/plugins";
  trek-secrets-env = "/run/trek/secrets.env";
  # Authoritative: dropping a plugin from here uninstalls it on the next start.
  trek-plugins = map trek-fetch-plugin [
    {
      id = "flight-tracker";
      src = "fbnlrz/trek-track@v1.8.0";
      hash = "sha256-IroHwJtXcFhtvlfIYRFSyUgwid4GWDPXOCSZGvGqPOA=";
      settings.aerodatabox_key = config.age.secrets.trek-aerodatabox-key.path;
    }
  ];
  trek-fetch-plugin = { id, src, hash, settings ? { } }:
    let parts = builtins.match "([^/]+)/([^@]+)@(.+)" src; in
    if parts == null
    then throw ''trek: plugin source must be "owner/repo@rev", got "${src}"''
    else {
      inherit id settings;
      src = pkgs.fetchzip {
        name = "trek-plugin-${id}";
        url = "https://github.com/${builtins.elemAt parts 0}/${
          builtins.elemAt parts 1}/archive/${builtins.elemAt parts 2}.tar.gz";
        inherit hash;
        # In the fetch, so the hash covers what is actually served.
        postFetch = ''
          find $out -name '*.html' -exec ${
            lib.getExe trek-pkg.passthru.injectUi} {} +
        '';
      };
    };
  trek-plugin-manifest = pkgs.writeText "trek-plugins" (lib.concatMapStrings
    (p: "${p.id} ${p.src}\n") trek-plugins);
  # Unsplash is absent deliberately: its env var outranks anything stored here.
  trek-admin-keys = {
    maps_api_key = config.age.secrets.trek-maps-key.path;
  };
  # A `{ file = …; }` value is read from that path at run time.
  trek-settings = {
    map_provider = "mapbox-gl";
    mapbox_access_token = { file = config.age.secrets.trek-mapbox-token.path; };
  };
  # Drives TREK's service classes directly: the admin API needs a session, and an
  # OIDC-only instance has no credential to present.
  trek-reconcile = pkgs.writeText "trek-reconcile.js" ''
    process.env.NODE_ENV = 'production';

    const fs = require('node:fs');
    const path = require('node:path');
    // This file is in the store; the code it drives is in the runtime tree.
    const serverRequire = require('node:module').createRequire(
      path.join(process.cwd(), 'noop.js'));
    serverRequire('tsconfig-paths/register');

    const { db } = serverRequire('./dist/db/database');
    const { discoverPlugins } = serverRequire('./dist/nest/plugins/install/discovery');
    const { PluginsService } = serverRequire('./dist/nest/plugins/plugins.service');
    const { PluginRuntimeService } = serverRequire('./dist/nest/plugins/plugin-runtime.service');
    const { encrypt_api_key } = serverRequire('./dist/services/apiKeyCrypto');
    const { setAdminUserDefaults } = serverRequire('./dist/services/settingsService');

    const declared = ${builtins.toJSON
      (map (p: { inherit (p) id settings; }) trek-plugins)};
    const adminKeys = ${builtins.toJSON trek-admin-keys};
    const settings = ${builtins.toJSON trek-settings};
    const pluginsService = new PluginsService();
    const runtime = new PluginRuntimeService();

    async function reconcilePlugins() {
      const { skipped } = discoverPlugins(db);
      for (const id of skipped) console.warn(`trek: plugin ''${id} failed discovery`);

      const wanted = new Set(declared.map((p) => p.id));
      for (const { id } of db.prepare('SELECT id FROM plugins').all()) {
        if (wanted.has(id)) continue;
        console.log(`trek: uninstalling undeclared plugin ''${id}`);
        await runtime.uninstall(id, false);
      }

      for (const { id, settings } of declared) {
        for (const [key, file] of Object.entries(settings)) {
          try {
            const value = fs.readFileSync(file, 'utf8').trim();
            if (value) pluginsService.updateInstanceConfig(id, { [key]: value });
          } catch (err) {
            console.warn(`trek: ''${id}.''${key} not set: ''${err.message}`);
          }
        }
        // Not runtime.activate(): that forks the plugin child here, and this
        // process exits mid-handshake (`child error: write EPIPE`). The server
        // spawns every enabled row itself, and stays alive to supervise it.
        db.prepare(
          "UPDATE plugins SET granted_permissions = permissions, enabled = 1, " +
          "status = 'inactive' WHERE id = ?").run(id);
      }
    }

    function syncAdminKeys() {
      // TREK falls back to any admin's copy, so one admin's key serves everyone.
      // None exists until a first SSO login, hence the no-op.
      const admin = db.prepare(
        "SELECT id FROM users WHERE role = 'admin' ORDER BY id LIMIT 1").get();
      for (const [column, file] of Object.entries(adminKeys)) {
        let value;
        try {
          value = fs.readFileSync(file, 'utf8').trim();
        } catch (err) {
          console.warn(`trek: ''${column} not set: ''${err.message}`);
          continue;
        }
        if (!value) continue;
        if (!admin) {
          console.log(`trek: ''${column} pending — no admin until a first SSO login`);
          continue;
        }
        db.prepare(`UPDATE users SET ''${column} = ? WHERE id = ?`)
          .run(encrypt_api_key(value), admin.id);
      }
    }

    function syncSettings() {
      const resolved = {};
      for (const [key, value] of Object.entries(settings)) {
        if (typeof value !== 'object' || value === null) { resolved[key] = value; continue; }
        try {
          const read = fs.readFileSync(value.file, 'utf8').trim();
          if (read) resolved[key] = read;
        } catch (err) {
          console.warn(`trek: ''${key} not set: ''${err.message}`);
        }
      }
      if (Object.keys(resolved).length) setAdminUserDefaults(resolved);
    }

    // Independent, and none worth failing the unit for: that keeps the site down
    // over stale config.
    async function main() {
      for (const step of [reconcilePlugins, syncAdminKeys, syncSettings]) {
        try {
          await step();
        } catch (err) {
          console.error(`trek: ''${step.name} failed: ''${err.message}`);
        }
      }
    }

    main().finally(() => process.exit(0));
  '';
in {
  site.apps.trek.enabled = true;

  age.secrets = {
    trek-oidc = {
      owner = "trek";
      file = ../secrets/oidc/trek-secret.age;
    };
    trek-aerodatabox-key = {
      owner = "trek";
      file = ../secrets/credentials/trek-aerodatabox-key.age;
    };
    trek-maps-key = {
      owner = "trek";
      file = ../secrets/credentials/trek-maps-key.age;
    };
    trek-mapbox-token = {
      owner = "trek";
      file = ../secrets/credentials/trek-mapbox-token.age;
    };
    trek-unsplash-key = {
      owner = "trek";
      file = ../secrets/credentials/trek-unsplash-key.age;
    };
  };

  systemd.services.trek = {
    description = "TREK collaborative travel planner";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    environment = {
      NODE_ENV = "production";
      PORT = toString trek.port;
      APP_URL = "https://${trek-domain}";
      TZ = config.time.timeZone;
      TRUST_PROXY = "1";
      FORCE_HTTPS = "false";
      COOKIE_SECURE = "true";
      TREK_PLUGINS_DIR = trek-plugins-dir;
      OIDC_ISSUER = "https://${config.site.apps.authelia.subdomain}.${config.site.domain}";
      OIDC_CLIENT_ID = "trek";
      OIDC_DISPLAY_NAME = "Authelia";
      OIDC_ONLY = "true";
      OIDC_SCOPE = "openid email profile groups";
      OIDC_ADMIN_CLAIM = "groups";
      OIDC_ADMIN_VALUE = trek.groups.admin;
    };
    preStart = ''
      find ${trek-runtime}/server -mindepth 1 -maxdepth 1 ${
        lib.concatMapStringsSep " " (n: "! -name ${n}") trek-pkg.stateLinks
      } -exec rm -rf {} +
      find ${trek-runtime} -mindepth 1 -maxdepth 1 ! -name server -exec rm -rf {} +
      for entry in ${trek-pkg}/lib/trek/*; do
        [ "$(basename "$entry")" = server ] && continue
        ln -s "$entry" ${trek-runtime}/"$(basename "$entry")"
      done
      for entry in ${trek-pkg}/lib/trek/server/*; do
        ln -s "$entry" ${trek-runtime}/server/"$(basename "$entry")"
      done
      # Real and writable, not a link (see passthru.stateLinks).
      rm -f ${trek-runtime}/server/dist
      cp -r ${trek-pkg}/lib/trek/server/dist ${trek-runtime}/server/dist
      chmod -R u+w ${trek-runtime}/server/dist
      ${lib.concatMapStringsSep "\n" (name: ''
        mkdir -p /var/lib/trek/${name}
        ln -sfn /var/lib/trek/${name} ${trek-runtime}/server/${name}
      '') trek-pkg.stateLinks}

      # Copied, not linked: discovery skips realpaths outside the plugins root.
      rm -rf ${trek-plugins-dir} || true
      install -d -m 0750 ${trek-plugins-dir}
      while read -r id path; do
        cp -r "$path" ${trek-plugins-dir}/"$id"
        chmod -R u+w ${trek-plugins-dir}/"$id"
      done < ${trek-plugin-manifest}

      umask 077
      # UNSPLASH_ACCESS_KEY, not the database: TREK reads it ahead of any stored key.
      { echo "OIDC_CLIENT_SECRET=$(cat ${config.age.secrets.trek-oidc.path})"
        echo "UNSPLASH_ACCESS_KEY=$(cat ${config.age.secrets.trek-unsplash-key.path})"
      } > ${trek-secrets-env}

      ${lib.getExe pkgs.nodejs} ${trek-reconcile}
    '';
    serviceConfig = {
      User = "trek";
      Group = "trek";
      ExecStart = "${lib.getExe trek-pkg}";
      Restart = "on-failure";
      RestartSec = 10;
      StateDirectory = "trek trek/runtime trek/runtime/server";
      RuntimeDirectory = "trek";
      RuntimeDirectoryMode = "0700";
      WorkingDirectory = "${trek-runtime}/server";
      EnvironmentFile = "-${trek-secrets-env}";
      # Hardening
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      ProtectKernelTunables = true;
      ProtectKernelModules = true;
      RestrictSUIDSGID = true;
      LimitNOFILE = 65536;
    };
  };

  users.users.trek = {
    isSystemUser = true;
    group = "trek";
  };

  users.groups.trek = { };

  services.caddy.virtualHosts.${trek-domain}.extraConfig = ''
    # Listed, not globbed: TREK serves its own /icons too.
    @custom-icons {
        path /icons/icon.svg
        path /icons/icon-192x192.png
        path /icons/icon-512x512.png
        path /icons/apple-touch-icon-180x180.png
    }
    handle @custom-icons {
        root ${config.site.assets}/trek
        file_server
    }
    reverse_proxy :${toString trek.port}
  '';
}

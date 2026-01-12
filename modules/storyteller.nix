{ config, lib, pkgs, ... }:

let
  storyteller = config.site.apps.storyteller;
  storyteller-domain = "${storyteller.subdomain}.${config.site.domain}";
  storyteller-pkg = pkgs.callPackage ../packages/storyteller.nix { whisper = pkgs.whisper-cpp-vulkan; };
  storyteller-import = "/data/media/books";
in {
  site.apps.storyteller.enabled = true;

  age.secrets.storyteller-oidc = {
    owner = "storyteller";
    file = ../secrets/storyteller-oidc-secret.age;
  };

  age.secrets.storyteller-smtp = {
    owner = "storyteller";
    file = ../secrets/fastmail.age;
  };

  systemd.services.storyteller = {
    description = "Storyteller synced audiobook platform";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    # Readium process management utilities
    path = with pkgs; [ lsof procps ];
    environment = {
      NODE_ENV = "production";
      PORT = toString storyteller.port;
      HOSTNAME = "0.0.0.0";
      READIUM_PORT = toString storyteller.readium-port;
      STORYTELLER_DATA_DIR = storyteller.dir;
      STORYTELLER_LOG_LEVEL = "info";
      STORYTELLER_SECRET_KEY_FILE = "${storyteller.dir}/secret_key";
      STORYTELLER_CONFIG = pkgs.writeText "storyteller-config.json" (builtins.toJSON {
        libraryName = "Books @ ${config.site.domain}";
        webUrl = "https://${storyteller-domain}";
        # importPath = storyteller-import;
        # importMode = "copy";
        authProviders = [{
          kind = "custom";
          name = "Authelia";
          issuer = "https://${config.site.apps.authelia.subdomain}.${config.site.domain}";
          clientId = "storyteller";
          clientSecret_file = config.age.secrets.storyteller-oidc.path;
          type = "oidc";
          allowRegistration = true;
          groupPermissions = lib.mkMerge ([{
            "${config.site.apps.storyteller.groups.admin}" = [
              "bookCreate" "bookRead" "bookProcess" "bookDownload" "bookList"
              "bookDelete" "bookUpdate" "collectionCreate" "inviteList"
              "inviteDelete" "userCreate" "userList" "userRead" "userDelete"
              "userUpdate" "settingsUpdate"];
          }] ++ (lib.map (g: { "${g}" = [ "bookRead" "bookDownload" "bookList" "bookCreate" ]; })
            [ config.site.apps.storyteller.groups.primary ] ++ storyteller.groups.extra));
        }];
        disablePasswordLogin = true;
        smtpHost = config.site.email.server;
        smtpPort = config.site.email.port;
        smtpUsername = config.site.email.username;
        smtpPassword_file = config.age.secrets.storyteller-smtp.path;
        smtpFrom = "Storyteller (${config.site.domain}) <services.storyteller@${config.site.domain}>";
        smtpSsl = true;
        smtpRejectUnauthorized = true;
      });
      ENABLE_WEB_READER = "true";
      HOME = storyteller.dir;
      # OIDC (trustHost is hardcoded true in Storyteller)
      AUTH_URL = "https://${storyteller-domain}/api/v2/auth";
      NEXT_CACHE_DIR = "%C/storyteller";
    };
    preStart = ''
      # Generate secret key on first launch
      if [ ! -s ${storyteller.dir}/secret_key ]; then
        umask 077
        head -c 32 /dev/urandom | base64 > ${storyteller.dir}/secret_key
      fi
    '';
    serviceConfig = {
      User = "storyteller";
      Group = "storyteller";
      ExecStart = "${storyteller-pkg}/bin/storyteller";
      Restart = "on-failure";
      RestartSec = 10;
      StateDirectory = "storyteller";
      CacheDirectory = "storyteller";
      # Hardening
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      PrivateTmp = true;
      ProtectHome = true;
      ProtectKernelTunables = true;
      ProtectKernelModules = true;
      LimitNOFILE = 65536;
    };
  };

  users.users.storyteller = {
    isSystemUser = true;
    group = "storyteller";
  };

  users.groups.storyteller = { };

  services.caddy.virtualHosts.${storyteller-domain}.extraConfig = ''
    root ${config.site.assets}/storyteller
    @logoimg {
        path /_next/image
        query url=/Storyteller_Logo.png
    }
    route /favicon.ico {
        file_server
    }
    route @logoimg {
        rewrite * /logo.png
        file_server
    }
    reverse_proxy :${toString storyteller.port}
  '';
}

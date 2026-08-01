{ config, lib, pkgs, utils, ... }:

let
  sftpgo-domain = "${config.site.apps.sftpgo.subdomain}.${config.site.domain}";
  sftpgo-user = "sftpgo";
  sftpgo-pkg = pkgs.callPackage ../packages/sftpgo.nix { };
  sftpgo-admin-user = "admin";
  sftpgo-exec = pkgs.writeShellScript "sftpgo-start" ''
    if [ -f "$CREDENTIALS_DIRECTORY/default-admin-password" ]; then
      export SFTPGO_DEFAULT_ADMIN_USERNAME="${sftpgo-admin-user}"
      export SFTPGO_DEFAULT_ADMIN_PASSWORD="$(${pkgs.coreutils}/bin/cat "$CREDENTIALS_DIRECTORY/default-admin-password")"
    fi
    [ -f "$CREDENTIALS_DIRECTORY/smtp-password" ] && \
      export SFTPGO_SMTP_PASSWORD="$(${pkgs.coreutils}/bin/cat "$CREDENTIALS_DIRECTORY/smtp-password")"
    exec ${sftpgo-pkg}/bin/sftpgo serve ${utils.escapeSystemdExecArgs config.services.sftpgo.extraArgs}
  '';
in {
  site.apps.sftpgo.enabled = true;

  age.secrets = {
    sftpgo-oidc = {
      owner = sftpgo-user;
      file = ../secrets/oidc/sftpgo-secret.age;
    };
    sftpgo-admin-password = {
      owner = sftpgo-user;
      file = ../secrets/passwords/sftpgo-admin-password.age;
    };
    sftpgo-smtp-password = {
      owner = sftpgo-user;
      file = ../secrets/credentials/fastmail.age;
    };
  };

  systemd.services.sftpgo.serviceConfig = {
    LoadCredential = [
      "default-admin-password:${config.age.secrets.sftpgo-admin-password.path}"
      "smtp-password:${config.age.secrets.sftpgo-smtp-password.path}"
    ];
    ExecStart = lib.mkForce sftpgo-exec;
  };

  networking.firewall.allowedTCPPorts = [
    config.site.apps.sftpgo.sftpd-port
    config.site.apps.sftpgo.webdavd-port
  ];

  nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [ "sftpgo" ];

  services.sftpgo = {
    enable = true;
    user = sftpgo-user;
    group = "users";
    package = sftpgo-pkg;
    extraReadWriteDirs = [ "/data/home" ];
    dataDir = config.site.apps.sftpgo.dir;
    settings = {
      common = {
        upload_mode = 2;
        defender.enable = true;
      };
      data_provider = {
        driver = "sqlite";
        name = "sftpgo.db";
        create_default_admin = true;
        password_hashing = {
          algo = "argon2id";
          argon2_options = {
            memory = 65536;
            iterations = 3;
            parallelism = 4;
          };
        };
        password_caching = true;
      };
      webdavd.bindings = [
        {
          address = "127.0.0.1";
          port = config.site.apps.sftpgo.webdavd-port;
          client_ip_proxy_header = "X-Forwarded-For";
          proxy_allowed = [ "127.0.0.1" ];
        }
      ];
      sftpd.bindings = [
        {
          port = config.site.apps.sftpgo.sftpd-port;
          client_ip_proxy_header = "X-Forwarded-For";
          address = "0.0.0.0";
        }
      ];
      httpd.bindings = [
        {
          address = "127.0.0.1";
          enable_https = false;
          port = config.site.apps.sftpgo.port;
          client_ip_proxy_header = "X-Forwarded-For";
          enable_web_admin = true;
          enable_web_client = true;
          enable_rest_api = true;
          enabled_login_methods = 6; # 0 = Anything, 1 = OIDC Admin, 2 = OIDC User, 4 = Form Admin, 8 = Form User
          proxy_allowed = [ "127.0.0.1" ];
          oidc = {
            client_id = "sftpgo";
            client_secret_file = config.age.secrets.sftpgo-oidc.path;
            config_url = "https://${config.site.apps.authelia.subdomain}.${config.site.domain}";
            redirect_base_url = "https://${sftpgo-domain}";
            scopes = [ "openid" "email" "profile" "groups" ];
            username_field = "preferred_username";
            custom_fields = [ "name" "email" ];
          };
          branding = {
            web_client = {
              name = "${config.site.domain}";
              short_name = "Files Web";
            };
            web_admin.short_name = "Files Admin";
          };
        }
      ];
      common = {
        proxy_protocol = 1;
        proxy_allowed = [ "127.0.0.1" ];
        proxy_skipped = [ ];
      };
      # smtp = {
      #   host = config.site.email.server;
      #   port = config.site.email.port;
      #   from = "${config.site.domain} — Storage <services.storage@${config.site.domain}>";
      #   user = config.site.email.username;
      #   # `password` set in ENV
      # };
    };
  };

  users.users."${sftpgo-user}".extraGroups =
    (lib.optional config.services.immich.enable "immich") ++
    (lib.optional config.services.paperless.enable "paperless");

  systemd.services.sftpgo.serviceConfig = {
    UMask = lib.mkForce "0007";
    Restart = "always";
    RestartSec = 5;
  };

  services.caddy.virtualHosts."${sftpgo-domain}".extraConfig =
    ''
    encode
    header -Alt-svc
    handle_path /static/img/* {
        root ${config.site.assets}/sftpgo
        file_server
    }
    handle /static/favicon.png {
        uri strip_prefix /static
        root ${config.site.assets}/sftpgo
        file_server
    }
    reverse_proxy * :${toString config.site.apps.sftpgo.port} {
        header_up Host {http.request.host}
        header_up Upgrade {http.request.header.Upgrade}
        header_up Connection {http.request.header.Connection}
    }
    '';
}

  # -- Configuration --

  /*
Virtual folders:
- backedup: Local disk (/data/home/backedup)
- immich: Local disk (/data/immich/library)
- paperless: Local disk (/data/paperless/media/documents/archive)
- shared: Local disk (/data/home/shared)

Action(Auto-create users): Identity Provider account check/Create or update:
{
    "status": 1,
    "username": "{{.Name}}",
    "email": "{{.IDPFieldemail}}",
    "home_dir": "/data/home/{{.Name}}",
    "permissions": {
        "/": ["*"],
        "/Photos": ["list", "download", "copy"],
        "/Shared": ["list", "download", "copy"],
        "/Shared/{{.IDPFieldname}}": ["*"],
        "/Documents/Archive": ["list", "download", "copy"]
    },
    "virtual_folders": [
        {
            "name": "shared",
            "virtual_path": "Shared"
        },
        {
            "name": "shared",
            "virtual_path": "Public",
            "subpath": "{{.IDPFieldname}}"
        },
        {
            "name": "immich",
            "virtual_path": "Photos",
            "subpath": "{{.Name}}"
        },
        {
            "name": "paperless",
            "virtual_path": "Documents/Archive",
            "subpath": "{{.Name}}"
        }
    ]
}

Action(New user skeleton): Filesystem/Create directories:
/Backed up/{{.IDPFieldname}},/Shared/{{.IDPFieldname}}

Rule(Auto-create OIDC user): Identity Provider Logins/User login:
- Actions:
  - Auto-create users [synchronous]
*/

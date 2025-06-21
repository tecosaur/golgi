{ config, lib, pkgs, ... }:

let
  sftpgo-domain = "${config.site.apps.sftpgo.subdomain}.${config.site.domain}";
  sftpgo-user = "sftpgo";
  sftpgo-pkg = pkgs.callPackage ../packages/sftpgo.nix { };
in {
  site.apps.sftpgo.enabled = true;

  age.secrets.sftpgo-oidc = {
    owner = sftpgo-user;
    group = "users";
    file = ../secrets/sftpgo-oidc-secret.age;
  };

  age.secrets.sftpgo-env = {
    owner = sftpgo-user;
    group = "users";
    file = ../secrets/sftpgo-env.age;
  };

  # Env secrents:
  # - SFTPGO_DEFAULT_ADMIN_USERNAME
  # - SFTPGO_DEFAULT_ADMIN_PASSWORD
  # - SFTPGO_SMTP_USER
  # - SFTPGO_SMTP_PASSWORD
  systemd.services.sftpgo.serviceConfig.EnvironmentFile =
    config.age.secrets.sftpgo-env.path;

  networking.firewall.allowedTCPPorts = [
    config.site.apps.sftpgo.sftpd-port
    config.site.apps.sftpgo.webdavd-port
  ];

  nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [
    "sftpgo"
  ];

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
          client_ip_proxy_header = "X-Real-IP";
          proxy_allowed = [ "127.0.0.1" ];
        }
      ];
      sftpd.bindings = [
        {
          port = config.site.apps.sftpgo.sftpd-port;
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
      #   host = "smtp.fastmail.com";
      #   port = 587;
      #   from = "${config.site.domain} — Storage <services.storage@${config.site.domain}>";
      #   # `user` set in ENV
      #   # `password` set in ENV
      # };
    };
  };

  users.users."${sftpgo-user}".group = lib.mkForce "users";
  users.groups."${sftpgo-user}".members = [
    "users"
    sftpgo-user
  ];

  systemd.services.sftpgo.serviceConfig = {
    UMask = lib.mkForce "0007";
  };

  services.caddy.virtualHosts."${sftpgo-domain}".extraConfig =
    ''
    encode
    header -Alt-svc
    handle_path /static/img/* {
        root * ${../assets/sftpgo}
        file_server
    }
    handle /static/favicon.png {
        uri strip_prefix /static
        root * ${../assets/sftpgo}
        file_server
    }
    reverse_proxy * :${toString config.site.apps.sftpgo.port} {
        header_up Host {http.request.host}
        header_up X-Real-IP {http.request.remote.host}
        header_up Upgrade {http.request.header.Upgrade}
        header_up Connection {http.request.header.Connection}
    }
    '';
}

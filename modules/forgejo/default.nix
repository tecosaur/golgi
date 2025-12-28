{ config, lib, pkgs, ... }:

let
  forgejo-user = "git";
  forgejo-domain = "${config.site.apps.forgejo.subdomain}.${config.site.domain}";
  blog-domain = "blog.${config.site.domain}";
  # theming
  catppuccinThemes = pkgs.fetchzip {
    url = "https://github.com/catppuccin/gitea/releases/download/v0.4.1/catppuccin-gitea.tar.gz";
    sha256 = "sha256-14XqO1ZhhPS7VDBSzqW55kh6n5cFZGZmvRCtMEh8JPI=";
    stripRoot = false;
  };
  catppuccinAutoThemes = pkgs.runCommand "catppuccin-auto-themes" { buildInputs = [ pkgs.coreutils ]; } ''
    mkdir -p $out
    for f in ${catppuccinThemes}/theme-catppuccin-latte-*.css; do
      f_frappe="$(echo "$f" | sed 's/latte/frappe/')"
      printf "@media (prefers-color-scheme: dark) {\n%s\n}\n\n@media (prefers-color-scheme: light){\n%s\n}" \
        "$(cat "$f_frappe")" "$(cat "$f")" > "$out/$(basename "$f_frappe")"
      f_macchiato="$(echo "$f" | sed 's/latte/macchiato/')"
      printf "@media (prefers-color-scheme: dark) {\n%s\n}\n\n@media (prefers-color-scheme: light){\n%s\n}" \
        "$(cat "$f_macchiato")" "$(cat "$f")" > "$out/$(basename "$f_macchiato")"
      f_mocha="$(echo "$f" | sed 's/latte/mocha/')"
      printf "@media (prefers-color-scheme: dark) {\n%s\n}\n\n@media (prefers-color-scheme: light){\n%s\n}" \
        "$(cat "$f_mocha")" "$(cat "$f")" > "$out/$(basename "$f_mocha")"
    done
  '';
in {
  site.apps.forgejo.enabled = true;

  age.secrets.postgres-forgejo = {
    owner = forgejo-user;
    group = "users";
    file = ../../secrets/postgres-forgejo.age;
  };

  age.secrets.fastmail = {
    owner = forgejo-user;
    group = "users";
    file = ../../secrets/fastmail.age;
  };

  services.forgejo = {
    enable = true;
    package = pkgs.forgejo;
    user = forgejo-user;
    group = forgejo-user;
    stateDir = config.site.apps.forgejo.dir;
    database = {
      type = "postgres";
      name = forgejo-user;
      user = forgejo-user;
      passwordFile = config.age.secrets.postgres-forgejo.path;
    };
    lfs.enable = true;
    secrets = {
      mailer.PASSWD = config.age.secrets.fastmail.path;
    };
    settings = {
      DEFAULT.APP_NAME = config.site.apps.forgejo.site-name;
      server = {
        DOMAIN = "${forgejo-domain}";
        ROOT_URL = "https://${forgejo-domain}";
        HTTP_ADDRESS = "0.0.0.0";
        HTTP_PORT = config.site.apps.forgejo.port;
      };
      mailer = {
        ENABLED = true;
        PROTOCOL = "smtp+startls";
        FROM = "noreply@${forgejo-domain}";
        USER = config.site.email.username;
        SMTP_ADDR = "${config.site.email.server}:${toString config.site.email.port}";
      };
      service = {
        REGISTER_EMAIL_CONFIRM = false;
        DISABLE_REGISTRATION = false;
        ALLOW_ONLY_EXTERNAL_REGISTRATION = true;
        SHOW_REGISTRATION_BUTTON = false;
      };
      openid = {
        ENABLE_OPENID_SIGNIN = false;
        ENABLE_OPENID_SIGNUP = false;
        WHITELISTED_URIS = "${config.site.apps.authelia.subdomain}.${config.site.domain}";
      };
      oauth2_client = {
        ENABLE_AUTO_REGISTRATION = true;
        ACCOUNT_LINKING = "auto";
        OPENID_CONNECT_SCOPES = "openid email profile groups";
        USERNAME = "userid";
      };
      indexer = {
        REPO_INDEXER_ENABLED = true;
        REPO_INDEXER_EXCLUDE = "**.pdf, **.png, **.jpeg, **.jpm, **.svg, **.webm";
      };
      repository = {
        DEFAULT_PRIVATE = "public";
        DEFAULT_PUSH_CREATE_PRIVATE = false;
        ENABLE_PUSH_CREATE_USER = true;
        PREFERRED_LICENSES = "GPL-3.0-or-later,MIT";
        DEFAULT_REPO_UNITS = "repo.code,repo.issues,repo.pulls";
      };
      # "repository.mimetype_mapping" = {
      #   ".org" = "text/org";
      # };
      # actions = {
      #   ENABLED = true;
      # };
      ui = {
        GRAPH_MAX_COMMIT_NUM = 200;
        THEME_COLOR_META_TAG = "#609926";
        DEFAULT_THEME = "gitea-auto";
        THEMES = let
          builtinThemes = [
            "forgejo-auto"
            "forgejo-light"
            "forgejo-dark"
            "gitea-auto"
            "gitea-light"
            "gitea-dark"
            "forgejo-auto-deuteranopia-protanopia"
            "forgejo-light-deuteranopia-protanopia"
            "forgejo-dark-deuteranopia-protanopia"
            "forgejo-auto-tritanopia"
            "forgejo-light-tritanopia"
            "forgejo-dark-tritanopia"
          ];
        in (builtins.concatStringsSep "," (
          builtinThemes
          ++ (map (name: lib.removePrefix "theme-" (lib.removeSuffix ".css" name)) (
            builtins.attrNames (builtins.readDir catppuccinAutoThemes)
          ))
        ));
      };
      "ui.meta" = {
        DESCRIPTION = config.site.apps.forgejo.site-description;
      };
      server = {
        SSH_DOMAIN = if config.site.cloudflare-bypass-subdomain == null then
          forgejo-domain else "${config.site.cloudflare-bypass-subdomain}.${config.site.domain}";
      };
      federation = {
        ENABLED = true;
      };
    };
  };

  # If forgejo is aggressively scrapped, it can
  # stall the entire system. Limit its resource usage.
  systemd.services.forgejo.serviceConfig = {
    MemoryAccounting = true;
    MemoryHigh = "768M";
    MemoryMax = "1G";
    MemorySwapMax = "1G";
    CPUAccounting = true;
    CPUQuota = "100%"; # Limit to one full core
  };

  users.users.${forgejo-user} = {
    home = config.services.forgejo.stateDir;
    useDefaultShell = true;
    group = forgejo-user;
    isSystemUser = true;
  };

  users.groups.${forgejo-user} = {};

  users.users.caddy.extraGroups = [ forgejo-user ];

  systemd.tmpfiles.rules = [
    "L+ ${config.services.forgejo.stateDir}/custom/templates/home.tmpl - - - - ${./template-home.tmpl}"
    "L+ ${config.services.forgejo.stateDir}/custom/public/assets/img/tree.svg - - - - ${../../assets/site/logo.svg}"
    "L+ ${config.services.forgejo.stateDir}/custom/public/assets/img/logo.svg - - - - ${../../assets/forgejo/favicon.svg}"
    "L+ ${config.services.forgejo.stateDir}/custom/public/assets/img/logo.png - - - - ${../../assets/forgejo/favicon.png}"
    "L+ ${config.services.forgejo.stateDir}/custom/public/assets/img/favicon.svg - - - - ${../../assets/forgejo/favicon.svg}"
    "L+ ${config.services.forgejo.stateDir}/custom/public/assets/img/favicon.png - - - - ${../../assets/forgejo/favicon.png}"
    "L+ ${config.services.forgejo.stateDir}/custom/public/assets/img/apple-touch-icon.png - - - - ${../../assets/forgejo/favicon.png}"
    "L+ ${config.services.forgejo.stateDir}/custom/public/assets/img/avatar_default.png - - - - ${../../assets/forgejo/avatar-default.png}"
    "L+ ${config.services.forgejo.stateDir}/custom/public/assets/css - - - - ${catppuccinAutoThemes}"
    "L+ ${config.services.forgejo.stateDir}/custom/public/robots.txt - - - - ${./robots.txt}"
  ];

  services.caddy = let
    processRepo = {repo, rev, subdomain, path}: let
      repo-nogit = lib.strings.removeSuffix ".git" repo;
      repo-parts = lib.strings.splitString "/" repo-nogit;
      user = builtins.elemAt repo-parts 0;
      repo-name = builtins.elemAt repo-parts 1;
      mkSafe = str: lib.stringAsChars (c: if builtins.match "^[A-Za-z0-9_]$" c != null then c else "_") str;
    in {
      repo = repo-nogit + ".git";
      rev = rev;
      subdomain = lib.strings.removeSuffix "." subdomain;
      path = if path != null then
        lib.strings.removeSuffix "/" (lib.strings.removePrefix "/" path)
             else "${user}/${repo-name}";
      fs = "git_${user}_${mkSafe repo-name}_${mkSafe rev}";
    };
    processed-repos = map processRepo config.site.apps.forgejo.served-repositories;
    subdomain-groups = lib.groupBy (entry: entry.subdomain) processed-repos;
    mkFsConfig = e:
      ''
      filesystem ${e.fs} git {
          repository ${config.services.forgejo.stateDir}/repositories/${e.repo}
          revision ${e.rev}
      }
      '';
    mkVhostEntry = e: ''
      redir /${e.path} /${e.path}/
      handle_path /${e.path}/* {
          fs ${e.fs}
          file_server
      }
      '';
    mkVhosts = groups:
      lib.mapAttrs' (sub: entries:
        lib.nameValuePair "${sub}.${config.site.domain}" {
          extraConfig = lib.concatStringsSep "\n" (map mkVhostEntry entries ++ [
            ''
            handle {
                respond 404
            }
            ''
          ]);
        }
      ) groups;
  in {
    globalConfig = lib.mkAfter (lib.concatStringsSep "\n" (map mkFsConfig processed-repos));
    virtualHosts =
      (mkVhosts subdomain-groups) //
      {
      "git.${config.site.domain}".extraConfig =
        "redir https://${forgejo-domain}{uri} 301";
      "${forgejo-domain}".extraConfig =
        ''
        handle {
            rewrite /user/login /user/oauth2/authelia
            reverse_proxy localhost:${toString config.services.forgejo.settings.server.HTTP_PORT}
        }
        '' + (if config.site.apps.forgejo.default-user-redirect != null then
          let user = config.site.apps.forgejo.default-user-redirect; in
          ''
          @not_${user} {
              not path /${user}/*
              not header Cookie *caddy_${user}_redirect=true*
          }
          handle @not_${user} {
              rewrite /user/login /user/oauth2/authelia
              reverse_proxy localhost:${toString config.services.forgejo.settings.server.HTTP_PORT} {
                  @404 status 404
                  handle_response @404 {
                      header +Set-Cookie "caddy_${user}_redirect=true; Max-Age=5"
                      redir * /${user}{uri}
                  }
              }
          }
          @${user}_redirect {
              path /${user}/*
              header Cookie *caddy_${user}_redirect=true*
          }
          handle @${user}_redirect {
              reverse_proxy localhost:${toString config.services.forgejo.settings.server.HTTP_PORT} {
                  @404 status 404
                  handle_response @404 {
                      header +Set-Cookie "caddy_${user}_redirect=true; Max-Age=0"
                      handle_path /${user}/* {
                          redir * {uri}
                      }
                  }
              }
          }
          '' else "");
      };
  };
}

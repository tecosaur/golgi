{ config, pkgs, ... }:

let
  forgejo-user = "git";
in {
  age.secrets.postgres = {
    owner = forgejo-user;
    group = "users";
    file = ../../secrets/postgres.age;
  };

  age.secrets.fastmail = {
    owner = forgejo-user;
    group = "users";
    file = ../../secrets/fastmail.age;
  };

  services.forgejo = {
    enable = true;
    user = forgejo-user;
    group = forgejo-user;
    stateDir = "/var/lib/forgejo";
    database = {
      type = "postgres";
      name = forgejo-user;
      user = forgejo-user;
      passwordFile = config.age.secrets.postgres.path;
    };
    lfs.enable = true;
    secrets = {
      mailer.PASSWD = config.age.secrets.fastmail.path;
    };
    settings = {
      DEFAULT.APP_NAME = "Code by TEC";
      server = {
        DOMAIN = "code.tecosaur.net";
        ROOT_URL = "https://code.tecosaur.net";
        HTTP_ADDRESS = "0.0.0.0";
        HTTP_PORT = 3000;
      };
      mailer = {
        ENABLED = true;
        PROTOCOL = "smtp+startls";
        FROM = "forgejo@code.tecosaur.net";
        USER = "tec@tecosaur.net";
        SMTP_ADDR = "smtp.fastmail.com:587";
      };
      service = {
        REGISTER_EMAIL_CONFIRM = true;
        DISABLE_REGISTRATION = true;
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
        DEFAULT_THEME = "auto";
        THEME_COLOR_META_TAG = "#609926";
      };
      "ui.meta" = {
        DESCRIPTION = "The personal forge of TEC";
      };
      federation = {
        ENABLED = true;
      };
    };
  };

  users.users.${forgejo-user} = {
    home = config.services.forgejo.stateDir;
    useDefaultShell = true;
    group = forgejo-user;
    isSystemUser = true;
  };

  users.groups.${forgejo-user} = {};

  systemd.tmpfiles.rules = [
    "L+ ${config.services.forgejo.stateDir}/custom/templates/home.tmpl - - - - ${./template-home.tmpl}"
    "L+ ${config.services.forgejo.stateDir}/custom/public/assets/img/tree-greentea-themed.svg - - - - ${./images/tree-greentea-themed.svg}"
    "L+ ${config.services.forgejo.stateDir}/custom/public/assets/img/logo.svg - - - - ${./images/forgejo-icon-greentea-themed.svg}"
    "L+ ${config.services.forgejo.stateDir}/custom/public/assets/img/logo.png - - - - ${./images/forgejo-icon-greentea-themed.png}"
    "L+ ${config.services.forgejo.stateDir}/custom/public/assets/img/favicon.svg - - - - ${./images/forgejo-icon-greentea-themed.svg}"
    "L+ ${config.services.forgejo.stateDir}/custom/public/assets/img/favicon.png - - - - ${./images/forgejo-icon-greentea-themed.png}"
    "L+ ${config.services.forgejo.stateDir}/custom/public/assets/img/apple-touch-icon.png - - - - ${./images/forgejo-icon-greentea-themed.png}"
    "L+ ${config.services.forgejo.stateDir}/custom/public/assets/img/avatar_default.png - - - - ${./images/forgejo-square-greentea-themed.png}"
  ];
}

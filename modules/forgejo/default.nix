{ config, pkgs, ... }:

{
  age.secrets.postgres-gitea = {
    owner = "gitea";
    group = "users";
    file = ../../secrets/postgres-gitea.age;
  };

  age.secrets.fastmail = {
    owner = "gitea";
    group = "users";
    file = ../../secrets/fastmail.age;
  };

  services.gitea = {
    package  = pkgs.forgejo;
    enable = true;
    user = "gitea";
    appName = "Code by TEC";
    database = {
      type = "postgres";
      passwordFile = config.age.secrets.postgres-gitea.path;
    };
    lfs.enable = true;
    mailerPasswordFile = config.age.secrets.fastmail.path;
    settings = {
      server = {
        DOMAIN = "git.tecosaur.net";
        ROOT_URL = "https://git.tecosaur.net";
        HTTP_ADDRESS = "0.0.0.0";
        HTTP_PORT = 3000;
      };
      mailer = {
        ENABLED = true;
        PROTOCOL = "smtp+startls";
        FROM = "forgejo@git.tecosaur.net";
        USER = "tec@tecosaur.net";
        HOST = "smtp.fastmail.com:587";
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

  # users.users.gitea.uid = 997;
  # users.enforceIdUniqueness = false;
  # users.users.git = {
  #   uid = config.users.users.gitea.uid;
  #   home = config.services.gitea.stateDir;
  #   useDefaultShell = true;
  #   group = "gitea";
  #   isSystemUser = true;
  # };

  systemd.tmpfiles.rules = [
    "L+ ${config.services.gitea.stateDir}/custom/templates/home.tmpl - - - - ${./template-home.tmpl}"
    "L+ ${config.services.gitea.stateDir}/custom/public/img/tree-greentea-themed.svg - - - - ${./images/tree-greentea-themed.svg}"
    "L+ ${config.services.gitea.stateDir}/custom/public/img/logo.svg - - - - ${./images/forgejo-icon-greentea-themed.svg}"
    "L+ ${config.services.gitea.stateDir}/custom/public/img/logo.png - - - - ${./images/forgejo-icon-greentea-themed.png}"
    "L+ ${config.services.gitea.stateDir}/custom/public/img/favicon.svg - - - - ${./images/forgejo-icon-greentea-themed.svg}"
    "L+ ${config.services.gitea.stateDir}/custom/public/img/favicon.png - - - - ${./images/forgejo-icon-greentea-themed.png}"
    "L+ ${config.services.gitea.stateDir}/custom/public/img/apple-touch-icon.png - - - - ${./images/forgejo-icon-greentea-themed.png}"
    "L+ ${config.services.gitea.stateDir}/custom/public/img/avatar_default.png - - - - ${./images/forgejo-square-greentea-themed.png}"
  ];
}

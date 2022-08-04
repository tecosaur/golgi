{ config, pkgs, ... }:

{
  age.secrets.postgress = {
    owner = "gitea";
    group = "users";
    file = ../../secrets/postgress.age;
  };

  age.secrets.fastmail = {
    owner = "gitea";
    group = "users";
    file = ../../secrets/fastmail.age;
  };

  services.gitea = {
    enable = true;
    user = "gitea";
    domain = "git.tecosaur.net";
    rootUrl = "https://git.tecosaur.net";
    httpAddress = "0.0.0.0";
    httpPort = 3000;
    appName = "Gitea";
    database = {
      type = "postgres";
      passwordFile = config.age.secrets.postgress.path;
    };
    disableRegistration = true;
    lfs.enable = true;
    mailerPasswordFile = config.age.secrets.fastmail.path;
    settings = {
      mailer = {
        # Update when https://github.com/go-gitea/gitea/pull/18982 is merged.
        ENABLED = true;
        MAILER_TYPE = "smtp";
        FROM = "gitea@tecosaur.net";
        USER = "tec@tecosaur.net";
        HOST = "smtp.fastmail.com:587";
        IS_TLS_ENABLED = false;
      };
      service = {
        REGISTER_EMAIL_CONFIRM = true;
      };
      indexer = {
        REPO_INDEXER_ENABLED = true;
        REPO_INDEXER_EXCLUDE = "**.pdf, **.png, **.jpeg, **.jpm, **.svg, **.webm";
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
    "L+ ${config.services.gitea.stateDir}/custom/public/img/tree-gitea-themed.svg - - - - ${./tree-gitea-themed.svg}"
  ];
}

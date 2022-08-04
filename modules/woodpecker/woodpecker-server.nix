{ config, lib, options, pkgs, ... }:

with lib;

let
  cfg = config.services.woodpecker-server;
  useMysql = cfg.database.type == "mysql";
  usePostgresql = cfg.database.type == "postgres";
  useSqlite = cfg.database.type == "sqlite3";
in
{
  options = {
    services.woodpecker-server = {
      enable = mkOption {
        default = false;
        type = types.bool;
        description = lib.mdDoc "Enable Woodpecker Server.";
      };

      stateDir = mkOption {
        default = "/var/lib/woodpecker-server";
        type = types.str;
        description = lib.mdDoc "woodpecker server data directory.";
      };

      user = mkOption {
        type = types.str;
        default = "woodpecker-server";
        description = lib.mdDoc "User account under which woodpecker server runs.";
      };

      rootUrl = mkOption {
        default = "http://localhost:3030";
        type = types.str;
        description = lib.mkDoc "Full public URL of Woodpecker server";
      };

      httpPort = mkOption {
        type = types.int;
        default = 3030;
        description = lib.mdDoc "HTTP listen port.";
      };

      gRPCPort = mkOption {
        type = types.int;
        default = 9000;
        description = lib.mdDoc "The gPRC listener port.";
      };

      admins = mkOption {
        default = "";
        type = types.str;
        description = lib.mdDoc "Woodpecker admin users.";
      };

      agentSecretFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = lib.mdDoc "Read the agent secret from this file path.";
      };

      database = {
        type = mkOption {
          type = types.enum [ "sqlite3" "mysql" "postgres" ];
          example = "mysql";
          default = "sqlite3";
          description = lib.mdDoc "Database engine to use.";
        };

        host = mkOption {
          type = types.str;
          default = "127.0.0.1";
          description = lib.mdDoc "Database host address.";
        };

        port = mkOption {
          type = types.port;
          default = (if !usePostgresql then 3306 else pg.port);
          defaultText = literalExpression ''
            if config.${opt.database.type} != "postgresql"
            then 3306
            else config.${options.services.postgresql.port}
          '';
          description = lib.mdDoc "Database host port.";
        };

        name = mkOption {
          type = types.str;
          default = "woodpecker-server";
          description = lib.mdDoc "Database name.";
        };

        password = mkOption {
          type = types.str;
          default = "";
          description = lib.mdDoc ''
            The password corresponding to {option}`database.user`.
            Warning: this is stored in cleartext in the Nix store!
            Use {option}`database.passwordFile` instead.
          '';
        };

        user = mkOption {
          type = types.str;
          default = "woodpecker-server";
          description = lib.mdDoc "Database user.";
        };

        socket = mkOption {
          type = types.nullOr types.path;
          default = if (cfg.database.createDatabase && usePostgresql) then "/run/postgresql" else if (cfg.database.createDatabase && useMysql) then "/run/mysqld/mysqld.sock" else null;
          defaultText = literalExpression "null";
          example = "/run/mysqld/mysqld.sock";
          description = lib.mdDoc "Path to the unix socket file to use for authentication.";
        };

        createDatabase = mkOption {
          type = types.bool;
          default = true;
          description = lib.mdDoc "Whether to create a local database automatically.";
        };
      };

      useGitea = mkOption {
        default = options.services.gitea.enabled;
        type = types.bool;
        description = lib.mkDoc "Whether to integrate with gitea.";
      };

      giteaUrl = mkOption {
        default = options.services.gitea.rootUrl;
        type = types.str;
        description = lib.mkDoc "Full public URL of gitea server.";
      };

      giteaClientIdFile = mkOption {
        type = types.nullOr types.path;
        default = null;
      };

      giteaClientSecretFile = mkOption {
        type = types.nullOr types.path;
        default = null;
      };
    };
  };

  config = mkIf cfg.enable {
    systemd.services.woodpecker-server = {
      description = "woodpecker-server";
      after = [ "network.target" ] ++ lib.optional usePostgresql "postgresql.service" ++ lib.optional useMysql "mysql.service";
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        Group = "woodpecker-server";
        WorkingDirectory = cfg.stateDir;
        ExecStart = "${pkgs.woodpecker-server}/bin/woodpecker-server";
        Restart = "always";
        # TODO add security/sandbox params.
      };
      environment = mkMerge [
        {
          WOODPECKER_OPEN=true;
          WOODPECKER_ADMIN=cfg.admins;
          WOODPECKER_HOST=cfg.rootUrl;
          WOODPECKER_SERVER_ADDR=":${toString cfg.httpPort}";
          WOODPECKER_GRPC_ADDR=cfg.gRPCPort;
        }
        (mkIf cfg.useGitea {
          WOODPECKER_GITEA=true;
          WOODPECKER_GITEA_URL=cfg.giteaUrl;
          WOODPECKER_GITEA_CLIENT_FILE=cfg.giteaClientIdFile;
          WOODPECKER_GITEA_SECRET_FILE=cfg.giteaClientSecretFile;
        })
        (mkIf usePostgresql {
          WOODPECKER_DATABASE_DRIVER="postgres";
          WOODPECKER_DATABASE_DATASOURCE=
            "postgres://${cfg.database.user}:${cfg.database.password}/${cfg.database.name}" +
            "?host=${if cfg.database.socket != null then cfg.database.socket else cfg.database.host + ":" + toString cfg.database.port}";
        })
        (mkIf (cfg.agentSecretFile != null) {
          WOODPECKER_AGENT_SECRET_FILE=cfg.agentSecretFile;
        })
      ];
    };

    services.postgresql = optionalAttrs (usePostgresql && cfg.database.createDatabase) {
      enable = mkDefault true;

      ensureDatabases = [ cfg.database.name ];
      ensureUsers = [
        { name = cfg.database.user;
          ensurePermissions = { "DATABASE ${cfg.database.name}" = "ALL PRIVILEGES"; };
        }
      ];
    };

    services.mysql = optionalAttrs (useMysql && cfg.database.createDatabase) {
      enable = mkDefault true;
      package = mkDefault pkgs.mariadb;

      ensureDatabases = [ cfg.database.name ];
      ensureUsers = [
        { name = cfg.database.user;
          ensurePermissions = { "${cfg.database.name}.*" = "ALL PRIVILEGES"; };
        }
      ];
    };

    users.users = mkIf (cfg.user == "woodpecker-server") {
      woodpecker-server = {
        createHome = true;
        home = cfg.stateDir;
        useDefaultShell = true;
        group = "woodpecker-server";
        extraGroups = [ "woodpecker" ];
        isSystemUser = true;
      };
    };
    users.groups.woodpecker-server = {  };
  };
}

{ config, lib, pkgs, ... }:

# With thanks to <https://github.com/xddxdd/nixos-config/blob/master/nixos/server-apps/crowdsec.nix>

let
  crowdsec-port = 8057;
  data-dir = config.services.crowdsec.settings.general.config_paths.data_dir;
  lapi-credentials = "${data-dir}/local_api_credentials.yaml";
  mkAcquisition =
    enable: unit:
    if enable then
      {
        source = "journalctl";
        journalctl_filter = [ "_SYSTEMD_UNIT=${unit}" ];
        labels.type = "syslog";
      }
    else
      null;
in {
  age.secrets.crowdsec-enroll-key = {
    owner = "crowdsec";
    group = "users";
    file = ../secrets/crowdsec-enroll-key.age;
  };

  services.crowdsec = {
    enable = true;
    autoUpdateService = true;
    localConfig = {
      acquisitions = builtins.filter (v: v != null) [
        (mkAcquisition config.services.openssh.enable "sshd.service")
        (mkAcquisition config.services.caddy.enable "caddy.service")
      ];
    };
    hub = {
      collections = [
        "crowdsecurity/linux"
        "crowdsecurity/caddy"
        "crowdsecurity/sshd"
      ];
      scenarios = [
        "crowdsecurity/http-bad-user-agent"
        "crowdsecurity/http-crawl-non_statics"
        "crowdsecurity/http-probing"
      ];
      postOverflows = [
        "crowdsecurity/cdn-qc-whitelsit"
        "crowdsecurity/cdn-whitelist"
        "crowdsecurity/discord-crawler-whitelist"
        "crowdsecurity/ipv6_to_range"
        "crowdsecurity/rdns"
        "crowdsecurity/seo-bots-whitelist"
      ];
    };
    settings = {
      simulation = { simulation = false; };
      lapi.credentialsFile = lapi-credentials;
      # `capi.credentialsFile` is deliberately unset: the setup script runs
      # `cscli machines add` (which loads the LAPI, and so reads the CAPI
      # credentials) before the `cscli capi register` that would create them,
      # so setting it aborts startup on a fresh install. Central API enrolment
      # happens through `console.tokenFile` below instead.
      console = {
        tokenFile = config.age.secrets.crowdsec-enroll-key.path;
      };
      general = {
        api.server = {
          enable = true;
          listen_uri = "127.0.0.1:${toString crowdsec-port}";
        };
      };
    };
  };

  # The nftables bouncer is what turns detections into bans, and still needs
  # enabling. `services.crowdsec-firewall-bouncer` with `registerBouncer.enable`
  # replaces the hand-rolled registration below, but its register service fails
  # with "open /etc/crowdsec/config.yaml: no such file": upstream passes the
  # generated config to the agent via `-c <store path>` and never populates
  # /etc/crowdsec, so a bare `cscli` finds nothing.

  # systemd.services.crowdsec = {
  #   postStart = ''
  #     set -euo pipefail
  #     export PATH="$PATH:${lib.makeBinPath [ pkgs.crowdsec ]}"
  #     alias cscli='${lib.getExe' pkgs.crowdsec "cscli"}'
  #     while ! cscli lapi status; do
  #       echo "Waiting for CrowdSec daemon to be ready"
  #       sleep 5
  #     done
  #     cscli bouncers add cs-firewall-bouncer --key cs-firewall-bouncer || true
  #   '';
  # };

  # services.crowdsec-firewall-bouncer = {
  #   enable = false;
  #   settings = {
  #     api_url = "http://127.0.0.1:${toString crowdsec-port}";
  #     api_key = "cs-firewall-bouncer";
  #     mode = "nftables";
  #     nftables = {
  #       ipv4 = {
  #         enabled = true;
  #         set-only = false;
  #         table = "crowdsec";
  #         chain = "crowdsec-chain";
  #       };
  #       ipv6 = {
  #         enabled = true;
  #         set-only = false;
  #         table = "crowdsec6";
  #         chain = "crowdsec6-chain";
  #       };
  #     };
  #   };
  # };

  # let
  #   csb-settings-file = (pkgs.formats.yaml { }).generate "crowdsec.yaml" {
  #     api_url = "http://127.0.0.1:${toString crowdsec-port}";
  #     api_key = "cs-firewall-bouncer";
  #     log_mode = "stdout";
  #     mode = "nftables";
  #     ipset_type = "nethash";
  #     update_frequency = "10s";
  #     deny_action = "DROP";
  #     blacklists_ipv4 = "crowdsec-blacklists";
  #     blacklists_ipv6 = "crowdsec6-blacklists";
  #     iptables_chains = [ "INPUT" ];
  #     nftables = {
  #       ipv4 = {
  #         enabled = true;
  #         set-only = false;
  #         table = "crowdsec";
  #         chain = "crowdsec-chain";
  #       };
  #       ipv6 = {
  #         enabled = true;
  #         set-only = false;
  #         table = "crowdsec6";
  #         chain = "crowdsec6-chain";
  #       };
  #     };
  #   };
  # in {
  #   systemd.services.crowdsec-firewall-bouncer = {
  #     description = "Crowdsec Firewall Bouncer";
  #     path = with pkgs; [ ipset iptables nftables ];
  #     wantedBy = [ "multi-user.target" ];
  #     partOf = [ "firewall.service" ];
  #     after = [ "crowdsec.service" ];
  #     requires = [ "crowdsec.service" ];
  #     serviceConfig = {
  #       Type = "notify"
  #         Restart = "always";
  #       RestartSec = 5;
  #       LimitNOFILE = 65536;
  #       MemoryDenyWriteExecute = true;
  #       CapabilityBoundingSet = [ "CAP_NET_ADMIN" "CAP_NET_RAW" ];
  #       NoNewPrivileges = true;
  #       LockPersonality = true;
  #       RemoveIPC = true;
  #       ProtectSystem = "strict";
  #       ProtectHome = true;
  #       PrivateTmp = true;
  #       PrivateDevices = true;
  #       PrivateHostname = true;
  #       ProtectKernelTunables = true;
  #       ProtectKernelModules = true;
  #       ProtectControlGroups = true;
  #       PRotectProc = "invisible";
  #       ProcSubset = "pid";
  #       RestrictNameSpaces = true;
  #       RestrictRealtime = true;
  #       RestrictSUIDSGID = true;
  #       SystemCallFilter = ["@system-service" "@network-io"];
  #       SystemCallArchitectures = "native";
  #       SystemCallErrorNumber = "EPERM";
  #       ExecPaths = [ "/nix/store" ];
  #       NoExecPaths = [ "/" ];
  #       ExecStartPre = "${pkgs.crowdsec-firewall-bouncer}/bin/cs-firewall-bouncer -t -c '${csb-settings-file}'";
  #       ExecStart = "${pkgs.crowdsec-firewall-bouncer}/bin/cs-firewall-bouncer -c '${csb-settings-file}'";
  #       ExecStartPost = "${pkgs.coreutils}/bin/sleep 0.2";
  #     };
  #   };
  # };
}

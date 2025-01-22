{ config, lib, pkgs, ... }:

# With thanks to <https://github.com/xddxdd/nixos-config/blob/master/nixos/server-apps/crowdsec.nix>

let
  crowdsec-port = 8057;
  configPath = "/var/lib/crowdsec/config";
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
    enrollKeyFile = config.age.secrets.crowdsec-enroll-key.path;
    allowLocalJournalAccess = true;
    acquisitions = builtins.filter (v: v != null) [
      (mkAcquisition config.services.openssh.enable "sshd.service")
      (mkAcquisition config.services.caddy.enable "caddy.service")
    ];
    settings = {
      config_paths = {
        simulation_path = "${configPath}/simulation.yaml";
      };
      api.server = {
        listen_uri = "127.0.0.1:${toString crowdsec-port}";
      };
    };
  };

  services.crowdsec-firewall-bouncer = {
    enable = false;
    settings = {
      api_url = "http://127.0.0.1:${toString crowdsec-port}";
      api_key = "cs-firewall-bouncer";
      mode = "nftables";
      nftables = {
        ipv4 = {
          enabled = true;
          set-only = false;
          table = "crowdsec";
          chain = "crowdsec-chain";
        };
        ipv6 = {
          enabled = true;
          set-only = false;
          table = "crowdsec6";
          chain = "crowdsec6-chain";
        };
      };
    };
  };

  systemd.services.crowdsec = {
    # Fix journald parsing error
    environment = {
      LANG = "C.UTF-8";
    };
    postStart = ''
      while ! cscli lapi status; do
        echo "Waiting for CrowdSec daemon to be ready"
        sleep 5
      done

      cscli bouncers add cs-firewall-bouncer --key cs-firewall-bouncer || true
    '';
    serviceConfig = {
      ExecStartPre = lib.mkAfter [
        (pkgs.writeShellScript "crowdsec-packages" ''
          cscli hub upgrade

          cscli collections install \
            crowdsecurity/linux \
            crowdsecurity/caddy \
            crowdsecurity/sshd

          cscli postoverflows install \
            crowdsecurity/cdn-qc-whitelsit \
            crowdsecurity/cdn-whitelist \
            crowdsecurity/discord-crawler-whitelist \
            crowdsecurity/ipv6_to_range \
            crowdsecurity/rdns \
            crowdsecurity/seo-bots-whitelist

          # Disable rules I do not want
          echo "simulation: false" > ${configPath}/simulation.yaml
          cscli simulation enable crowdsecurity/http-bad-user-agent
          cscli simulation enable crowdsecurity/http-crawl-non_statics
          cscli simulation enable crowdsecurity/http-probing
        '')
      ];

      StateDirectory = "crowdsec";
      Restart = lib.mkForce "always";
      RestartSec = lib.mkForce "5";
    };
  };

  systemd.services.crowdsec-firewall-bouncer =
    lib.mkIf config.services.crowdsec-firewall-bouncer.enable
      {
        after = [ "crowdsec.service" ];
        requires = [ "crowdsec.service" ];
        serviceConfig = {
          Restart = lib.mkForce "always";
          RestartSec = lib.mkForce "5";
        };
      };
}

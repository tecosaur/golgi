{ config, lib, pkgs, ... }:

let
  ha-domain = "${config.site.apps.home-assistant.subdomain}.${config.site.domain}";
  ha-state = "/var/lib/hass/state";
  ha-state-files = [ "home-assistant_v2.db" "automations.yaml" ];
  hax-bambu = pkgs.home-assistant.python3Packages.callPackage ../packages/ha-bambu.nix { };
  hax-bom = pkgs.home-assistant.python3Packages.callPackage ../packages/ha-bom.nix { };
  hax-vzug = pkgs.home-assistant.python3Packages.callPackage ../packages/ha-vzug.nix { };
in {
  site.apps.home-assistant.enabled = true;

  # Only a directory can be bind-mounted, and some of this state is loose files;
  # linking them into one gathers it all under a single mount.
  systemd.services.home-assistant.preStart = lib.mkBefore ''
    # Not mkdir: data-mounts binds this, and creating it would mask a failed mount.
    [ -d ${ha-state} ] || { echo "hass: ${ha-state} is missing" >&2; exit 1; }
    ${lib.concatMapStringsSep "\n" (f: ''
      if [ -f /var/lib/hass/${f} ] && [ ! -L /var/lib/hass/${f} ]; then
        if [ -e ${ha-state}/${f} ]; then
          echo "hass: both /var/lib/hass/${f} and ${ha-state}/${f} exist;" \
               "remove whichever is stale" >&2
          exit 1
        fi
        mv /var/lib/hass/${f} ${ha-state}/${f}
      fi
      ln -sfn ${ha-state}/${f} /var/lib/hass/${f}
    '') ha-state-files}
  '';

  age.secrets.home-assistant-secrets = {
    owner = "hass";
    group = "users";
    file = ../secrets/credentials/home-assistant-secrets.age;
    path = "/var/lib/hass/secrets.yaml";
  };

  services.home-assistant = {
    enable = true;
    extraComponents = [
      "apple_tv"
      "aussie_broadband"
      "apollo_automation"
      "brother"
      "camera"
      "esphome"
      "immich"
      "linkplay"
      "mealie"
      "met"
      "mikrotik"
      "music_assistant"
      "nanoleaf"
      "ntfy"
      "radio_browser"
      "stream"
      "squeezebox"
      "thread"
      "zeroconf"
    ];
    customComponents = with pkgs.home-assistant-custom-components; [
      adaptive_lighting
      hax-bambu
      hax-bom
      hax-vzug
    ];
    customLovelaceModules = with pkgs.home-assistant-custom-lovelace-modules; [
      mushroom
      mini-graph-card
      mini-media-player
      weather-card
      weather-chart-card
      clock-weather-card
      hourly-weather
      universal-remote-card
    ];
    config = {
      http = {
        base_url = "https://${ha-domain}";
        server_port = config.site.apps.home-assistant.port;
        use_x_forwarded_for = true;
        trusted_proxies = "127.0.0.1";
      };
      default_config = {};
      automation = "!include automations.yaml";
      homeassistant = {
        time_zone = "!secret time_zone";
      };
      zone = [
        {
          name = "Home";
          icon = "mdi:home";
          latitude = "!secret home_latitude";
          longitude = "!secret home_longitude";
          radius = 80;
        }
      ];
    };
  };

  services.caddy.virtualHosts."${ha-domain}".extraConfig =
    ''
    reverse_proxy :${toString config.site.apps.home-assistant.port}
    '';
}

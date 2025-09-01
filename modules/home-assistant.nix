{ config, lib, pkgs, ... }:

let
  ha-domain = "${config.site.apps.home-assistant.subdomain}.${config.site.domain}";
  hax-bambu = pkgs.home-assistant.python.pkgs.callPackage ../packages/ha-bambu.nix { };
  hax-bom = pkgs.home-assistant.python.pkgs.callPackage ../packages/ha-bom.nix { };
  hax-vzug = pkgs.home-assistant.python.pkgs.callPackage ../packages/ha-vzug.nix { };
in {
  site.apps.home-assistant.enabled = true;

  age.secrets.home-assistant-secrets = {
    owner = "hass";
    group = "users";
    file = ../secrets/home-assistant-secrets.age;
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
      "mealie"
      "met"
      "mikrotik"
      "music_assistant"
      "nanoleaf"
      "ntfy"
      "radio_browser"
      "stream"
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

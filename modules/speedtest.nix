{ config, lib, pkgs, ... }:

let
  speed-domain = "${config.site.apps.speedtest.subdomain}.${config.site.domain}";
in {
  site.apps.speedtest.enabled = true;

  services.librespeed = {
    enable = true;
    frontend = {
      enable = true;
      pageTitle = "Speed Test";
      contactEmail = "speedtest@${config.site.domain}";
      servers = [{
        name = speed-domain;
        server = "https://${speed-domain}";
      }];
    };
    settings = {
      listen_port = config.site.apps.speedtest.port;
      enable_tls = false;
    };
  };

  services.caddy.virtualHosts."${speed-domain}".extraConfig =
    ''
    import auth
    route {
      root ${config.services.librespeed.settings.assets_path}
      reverse_proxy /backend/* :${toString config.site.apps.speedtest.port} {
        header_up X-Real-IP {http.request.remote.host}
      }
      respond /servers.json <<JSON
         ${builtins.toJSON config.services.librespeed.frontend.servers}
         JSON 200
      file_server
    }
    '';
}

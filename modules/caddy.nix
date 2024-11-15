{ config, lib, pkgs, ... }:

with lib;

{
  networking.firewall.allowedTCPPorts = [ 80 443 ];
  networking.firewall.allowedUDPPorts = [ 443 ];

  services.caddy = {
      enable = true;
      package = pkgs.callPackage ../packages/caddy.nix {
        externalPlugins = [
          {name = "caddy-fs-git"; repo = "github.com/tecosaur/caddy-fs-git";
           version = "ef9d0ab232f4fe5d7e86312cbba45ff8afea98a1";}
          {name = "replace-response"; repo = "github.com/caddyserver/replace-response";
           version = "f92bc7d0c29d0588f91f29ecb38a0c4ddf3f85f8";}
        ];
        vendorHash = "sha256-SFepy3A/Dxqnke78lwzxGmtctkUpgnDU3uVhCxLQAQ0=";
      };
      virtualHosts."${config.site.domain}".extraConfig = ''
@assets path /favicon.ico
file_server @assets {
  root /etc/site-assets
}
respond / "  ⠀      ⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣀⣀⣀⣀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
        ⠀⠀⠀⠀⠀⠀⠀⢀⣠⣴⣾⣿⣿⣿⣿⣿⣿⣿⣷⣆⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
        ⠀⠀⠀⢀⣤⣶⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣟⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
        ⠀⠀⠀⠈⢙⣿⣿⣿⣿⣿⣿⡿⠻⣿⣴⡿⠿⣿⣿⣿⣿⣷⣶⡄⠀⠀⠀⠀⠀⠀
        ⠀⠀⠀⠘⠛⠛⠛⠋⠉⠙⢿⠁⠀⢻⣿⣿⣿⣿⣿⣿⣿⣾⣿⣥⡄⠀⠀⠀⠀⠀
        ⠀⠀⠀⢾⣿⣿⣿⣷⣤⣄⣈⡇⢀⣸⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣇⠀⠀⠀⠀⠀
        ⠀⠀⠀⢀⣿⣿⣿⣿⣷⣾⣿⣿⡿⢿⡿⠿⢿⣿⣿⣿⣿⣿⣿⣿⣿⣦⠀⠀⠀⠀
        ⠀⣴⣶⣿⡿⠿⢿⡿⠿⠛⠉⠹⣇⢸⡇⠠⣾⠿⢷⣶⣶⣶⣶⣾⣏⣁⣀⣀⠀⠀
        ⠀⠀⠀⠀⢀⣴⣶⣶⣶⣶⣶⠶⠿⣾⡇⣸⠃⣠⡾⠛⣿⣿⣿⡟⠻⠿⠛⠉⠀⠀
        ⠀⢀⣠⣴⠿⠿⠿⣿⣿⣿⡿⢷⡀⣹⣷⡟⢠⡿⣠⢬⣽⣷⣾⣶⣦⣤⣀⠀⠀⠀
        ⠀⠸⡿⠃⠀⣀⣀⣠⣤⣤⣤⣌⠳⣿⡟⠀⣾⣇⡏⠀⠻⢿⣿⣿⣿⣿⣿⠗⠀⠀
        ⠀⠀⠀⠀⠸⠟⠋⣿⣿⣯⣉⠉⠙⣿⣷⣾⠿⢛⣶⣶⣶⣶⣿⣿⣿⣿⡀⠀⠀⠀
        ⠀⠀⠀⠀⠀⠀⠈⠉⠛⠋⠉⠁⠀⣿⣿⡏⠀⠸⠿⠿⠿⠿⣿⣿⣿⣿⣿⡿⠟⠀
        ⠀⠀⠀⠀⠀⠀⠀⠀⠰⢾⣷⣶⣶⣿⣿⣷⣶⡶⠦⠀⠀⠀⠀⠀⠉⠙⠋⠀⠀⠀
                      ⠉⠉⠉

This is my personal general-purpose server, where I
host various services, projects, and utilities.

__        __   _
\ \      / /__| | ___ ___  _ __ ___   ___
 \ \ /\ / / _ \ |/ __/ _ \| '_ ` _ \ / _ \
  \ V  V /  __/ | (_| (_) | | | | | |  __/
   \_/\_/ \___|_|\___\___/|_| |_| |_|\___|

If you're interested in the projects I'm working on,
and increacing number of them are hosted on
<https://${config.site.apps.forgejo.subdomain}.${config.site.domain}>.

Occasionally I write about developments in Org Mode,
and put them on <https://blog.${config.site.domain}/tmio>.
I also have a collection of public documents under
<https://public.${config.site.domain}>.

Enjoy!

┌╴───────────────╶┐
| Online presence |
└╴───────────────╶┘

• @tecosaur on Github: <https://github.com/tecosaur>
• @tecosaur around Julia spaces:
  – Discourse <https://discourse.julialang.org/u/tecosaur>
  – Zulip <https://julialang.zulipchat.com>
  – Slack <https://julialang.slack.com>
• @tecosaur:matrix.org
• @tecosaur on Discord
• @tecosaur (with a tree avatar) around the net…

I'm generally happy to be contacted, and can also be reached
by email at contact@<this domain>.

┌╴─────────────────╶┐
| Technical details |
└╴─────────────────╶┘

This server is managed by NixOS (with flakes and deploy-rs),
and is composed of:
${concatStringsSep "\n" (map (app: "• ${app.name} (${app.description})")
  (builtins.filter (app: app.enabled) (builtins.attrValues config.site.apps)))}

In future, I'm also considering setting up:
• Dendrite/Conduit (Matrix servers)
• My TMiO blog
• Kopia (backups)
• Koel (music streaming)
"
  '';
  };

  environment.etc."site-assets/favicon.ico" = {
    source = ../assets/site/favicon.ico;
    mode = "0444";
  };

  users.users.caddy = {
    extraGroups =
      lib.optional config.services.syncthing.enable config.services.syncthing.user ++
      lib.optional config.services.forgejo.enable   config.services.forgejo.user;
  };
}

{ config, lib, pkgs, ... }:

with lib;

let
  mkAppExport = name: app: let
    prefix = lib.toUpper (lib.replaceStrings [ "-" ] [ "_" ] name);
  in
    ''
    export ${prefix}_SUBDOMAIN="${app.subdomain}";
    export ${prefix}_URL="${app.subdomain}.${config.site.domain}";
    '';
  mkAppExports = apps: lib.concatStringsSep "\n"
    (lib.attrsets.mapAttrsToList mkAppExport
      (lib.filterAttrs (_: v: v.enabled) apps));
  apps-exports = mkAppExports config.site.apps;
  static-root = pkgs.runCommand "static-root" { buildInputs = [ pkgs.gettext ]; } ''
      export DOMAIN='${config.site.domain}'
      export FORGE_SUBDOMAIN='${config.site.apps.forgejo.subdomain}'
      export HOMEPAGE_SUBDOMAIN='${config.site.apps.homepage.subdomain}'
      ${apps-exports}
      export APPS_TEXT=$(cat <<'HEREDOC'
      ${concatStringsSep "\n" (map (app: "• ${app.name} (${app.description})")
        (builtins.filter (app: app.enabled) (builtins.attrValues config.site.apps)))}
      HEREDOC
      )

      apply_template() {
          for file in "$@"; do
              tmpout=$(mktemp)
              envsubst < "$file" > "$tmpout"
              mv "$tmpout" "$file"
          done
      }

      mkdir -p $out
      cp -r ${../assets/site}/* $out
      cd $out
      apply_template index.txt welcome-public.html welcome-private.html
      cp index.html index-public.html
      export WELCOME=`sed 's/^/            /g' welcome-public.html`
      apply_template index-public.html
      cp index.html index-private.html
      export WELCOME=`sed 's/^/            /g' welcome-private.html`
      apply_template index-private.html
      rm index.html welcome-public.html welcome-private.html
      apply_template services.html
    '';
in {
  services.caddy = {
      virtualHosts."${config.site.domain}".extraConfig = ''
        @browser-auth {
            header User-Agent *Mozilla*
            header Cookie *authelia_session*
        }
        @browser header User-Agent *Mozilla*
        try_files {path} {path}.html
        root * ${static-root}
        route {
            file_server @browser-auth {
              index index-private.html
            }
            file_server @browser {
              index index-public.html
            }
            file_server {
              index index.txt
            }
        }
        '';
  };
}

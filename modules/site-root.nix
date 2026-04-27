{ config, lib, pkgs, ... }:

with lib;

let
  mkAppExport = name: app: let
    prefix = lib.toUpper (lib.replaceStrings [ "-" ] [ "_" ] name);
    allGroups = [ app.groups.primary ] ++                                                                                                              
                (lib.optional (app.groups.admin != null) app.groups.admin) ++                                                                                    
                app.groups.extra;  
    groupChecks =  "(any " + (lib.concatStringsSep " " (map (g: ''(contains "${g}" $groups)'') allGroups)) + ")";
  in
    if app.enabled then
      {
        "${prefix}_SUBDOMAIN" = app.subdomain;
        "${prefix}_URL" = "${app.subdomain}.${config.site.domain}";
        "${prefix}_ACCESS" = "(or (not $groups) ${groupChecks})";
        "${prefix}_ENABLED" = "true";
      } else
        {
          "${prefix}_SUBDOMAIN" = "<unknown>";
          "${prefix}_URL" = "${config.site.domain}";
          "${prefix}_ACCESS" = "false";
          "${prefix}_ENABLED" = "false";
        };
  apps-exports = lib.concatMapAttrs mkAppExport config.site.apps;
  apps-env-export = lib.concatStringsSep "\n" (lib.mapAttrsToList
    (key: val: "export ${key}='${val}'")
    apps-exports);
  app-env-vars = lib.concatStringsSep " " (lib.mapAttrsToList (k: _: "\$${k}") apps-exports);
  static-root = pkgs.runCommand "static-root" { buildInputs = [ pkgs.gettext ]; } ''
      export DOMAIN='${config.site.domain}'
      export ACCENT='${config.site.accent.primary}'
      ${apps-env-export}
      export APPS_TEXT=$(cat <<'HEREDOC'
      ${concatStringsSep "\n" (map (app: "• ${app.name} (${app.description})")
        (builtins.filter (app: app.enabled) (builtins.attrValues config.site.apps)))}
      HEREDOC
      )

      apply_template() {
          for file in "$@"; do
              tmpout=$(mktemp)
              envsubst '$DOMAIN $ACCENT $APPS_TEXT $WELCOME ${app-env-vars}' < "$file" > "$tmpout"
              mv "$tmpout" "$file"
          done
      }

      mkdir -p $out
      cp -r ${config.site.assets}/site/* $out
      cd $out
      apply_template index.txt welcome-public.html welcome-private.html
      cp index.html index-public.html
      export WELCOME=`sed 's/^/            /g' welcome-public.html`
      apply_template index-public.html
      cp index.html index-private.html
      export WELCOME=`sed 's/^/            /g' welcome-private.html`
      apply_template index-private.html
      rm index.html welcome-public.html welcome-private.html
      apply_template services.html # about.html
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
        templates
        root ${static-root}
        route {
            handle /reload {
                header Clear-Site-Data "\"cache\""
                redir * /
            }
            handle @browser-auth {
                import auth
                file_server {
                    index index-private.html
                }
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

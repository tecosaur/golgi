{ config, lib, pkgs, ... }:

let
  mkClient = app: overrides@{
    client_secret ? null,
    redirect_paths ? null,
    redirect_uris ? null,
    require_pkce ? true,
    force ? false,
    ...
  }:
    let
      readSecret = name:
        lib.removeSuffix "\n" (builtins.readFile (../../secrets + "/${name}-oidc-secret.txt"));
      pathsToUris = ps:
        map (p: "https://${app.subdomain}.${config.site.domain}/${p}") ps;
      oidcRedirects = (if redirect_paths != null then
        pathsToUris redirect_paths else
          []) ++ (if redirect_uris != null then redirect_uris else []);
      safeName = lib.toLower (lib.replaceStrings [ " " ] [ "-" ] app.name);
      baseClient = {
        client_id = safeName;
        client_name = app.name;
        authorization_policy = safeName;
        client_secret = if client_secret != null then
          client_secret else readSecret safeName;
        public = false;
        consent_mode = "implicit";
        require_pkce = require_pkce;
        pkce_challenge_method = if require_pkce then "S256" else "";
        redirect_uris = oidcRedirects;
        scopes = [ "openid" "email" "profile" "groups" ];
        access_token_signed_response_alg = "none";
        response_types = [ "code" ];
        grant_types = [ "authorization_code" ];
        userinfo_signed_response_alg = "none";
        token_endpoint_auth_method = "client_secret_basic";
      };
      cleanedOverrides = builtins.removeAttrs
        overrides [ "client_secret" "redirect_paths" "redirect_uris" "force" ];
    in
      lib.optionals (force || app.enabled)
        [(baseClient // cleanedOverrides)];
  mkPolicy = app: {
    default_policy ? "deny",
    user_policy ? "one_factor",
    admin_policy ? "two_factor",
    extra_groups ? [],
    admins ? false,
    rules ? null,
    force ? false,
  }:
    lib.optionalAttrs (force || app.enabled) {
      "${lib.toLower (lib.replaceStrings [ " " ] [ "-" ] app.name)}" =
        {
          default_policy = default_policy;
          rules = if rules != null then rules else
            (if user_policy == admin_policy then
              [{
                policy = user_policy;
                subject = [ "group:${app.user-group}"
                            "group:${app.admin-group}" ] ++
                (lib.map (g: "group:${g}") extra_groups);
              }] else
                [{
                  policy = user_policy;
                  subject = if extra_groups != [] then
                    [ "group:${app.user-group}" ] ++
                    (lib.map (g: "group:${g}") extra_groups) else
                      "group:${app.user-group}";
                }] ++ (if admins then
                  [{
                    policy = admin_policy;
                    subject = "group:${app.admin-group}";
                  }] else [])
            );
        };
    };
  mkAccessControl = app: {
    policy ? "one_factor",
    subject ? null,
    force ? false,
  }:
    let
      domain = "${app.subdomain}.${config.site.domain}";
      rules = [
        {
          domain = domain;
          policy = policy;
          subject = if subject != null then subject else
            [ "group:${app.user-group}"
              "group:${app.admin-group}" ];
        }
        {
          domain = domain;
          policy = "deny";
        }
      ];
    in
      lib.optionals (force || app.enabled) rules;
in {
  services.authelia.instances.main.settings = {
    identity_providers.oidc = {
      authorization_policies = lib.mkMerge [
        (mkPolicy config.site.apps.forgejo {
          user_policy = "one_factor";
        })
        (mkPolicy config.site.apps.headscale {
          admins = false;
        })
        (mkPolicy config.site.apps.immich {
          user_policy = "one_factor";
          extra_groups = [ "family" ];
        })
        (mkPolicy config.site.apps.memos {
          extra_groups = [ "family" ];
        })
        (mkPolicy config.site.apps.vikunja {
          user_policy = "two_factor";
        })
        (mkPolicy config.site.apps.paperless {
          user_policy = "two_factor";
          extra_groups = [ "family" ];
        })
        (mkPolicy config.site.apps.sftpgo {
          user_policy = "two_factor";
          extra_groups = [ "family" ];
          admins = false;
        })
      ];
      claims_policies = {
        sftpgo = {
          # An ugly hack because SFTPGo doesn't support the bare
          # minimum of an OIDC client 🙃.
          id_token = [ "preferred_username" "email" "name" ];
        };
      };
      clients = lib.flatten [
        (mkClient config.site.apps.calibre-web {
          redirect_paths = [ "login/generic/authorized" ];
          require_pkce = false;
          authorization_policy = "one_factor";
        })
        (mkClient config.site.apps.forgejo {
          redirect_paths = [ "user/oauth2/authelia/callback" ];
        })
        (mkClient config.site.apps.headscale {
          redirect_paths = [ "oidc/callback" "admin/oidc/callback" ];
        })
        (mkClient config.site.apps.immich {
          redirect_paths = [ "auth/login" "user-settings" ];
          redirect_uris = [ "app.immich:///oauth-callback" ];
          response_types = [ "code" ];
          require_pkce = false;
          token_endpoint_auth_method = "client_secret_post";
        })
        (mkClient config.site.apps.jellyfin {
          redirect_paths = [ "sso/OID/redirect/authelia" ];
          authorization_policy = "one_factor";
          token_endpoint_auth_method = "client_secret_post";
        })
        (mkClient config.site.apps.mealie {
          authorization_policy = "one_factor";
          redirect_paths = [ "login" ];
          redirect_uris = [ "http://localhost:${toString config.site.apps.mealie.port}/login" ];
        })
        (mkClient config.site.apps.memos {
          redirect_paths = [ "auth/callback" ];
          require_pkce = false;
          token_endpoint_auth_method = "client_secret_post";
        })
        (mkClient config.site.apps.paperless {
          redirect_paths = [ "accounts/oidc/authelia/login/callback/" ];
        })
        (mkClient config.site.apps.sftpgo {
          authorization_policy = "one_factor";
          claims_policy = "sftpgo";
          redirect_paths = [ "web/oidc/redirect" "web/oauth2/redirect" ];
        })
        (mkClient config.site.apps.vikunja {
          redirect_paths = [ "auth/openid/authelia" ];
        })
      ];
    };
    access_control.rules = lib.flatten [
      (mkAccessControl config.site.apps.microbin {
        policy = "one_factor";
      })
      (mkAccessControl config.site.apps.ntfy {
        policy = "two_factor";
      })
      (mkAccessControl config.site.apps.uptime {
        policy = "one_factor";
      })
    ];
  };
}

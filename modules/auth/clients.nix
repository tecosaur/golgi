{ config, lib, pkgs, ... }:

let
  mkClient = app: overrides@{
    client_secret,
    redirect_paths ? null,
    redirect_uris ? null,
    force ? false,
    ...
  }:
    let
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
        client_secret = client_secret;
        public = false;
        consent_mode = "implicit";
        require_pkce = true;
        pkce_challenge_method = "S256";
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
          client_secret = "$argon2id$v=19$m=65536,t=3,p=4$w8Z9XPzJzP+ZM4DvPZ2EyA$KsUuWk7eE/MnHc/YaFDLuNsWeKHYA/SbQ2AfpSijfuo";
          redirect_paths = [ "login/generic/authorized" ];
          require_pkce = false;
          pkce_challenge_method = "";
          authorization_policy = "one_factor";
        })
        (mkClient config.site.apps.forgejo {
          client_secret = "$argon2id$v=19$m=65536,t=3,p=4$fRdkE7fHqAPkVQYXn1Zksw$O6WQ4fsNoN/0vzOK4hT1oreVPyFoVcK2hOIFx3axe/A";
          redirect_paths = [ "user/oauth2/authelia/callback" ];
        })
        (mkClient config.site.apps.headscale {
          client_secret = "$argon2id$v=19$m=65536,t=3,p=4$JxZLRd3W145f3uB3D2UVqw$kJVGMuaLzESu9kWDYE8p8mnM2qRRAiaLgAI0vJaCu5k";
          redirect_paths = [ "oidc/callback" "admin/oidc/callback" ];
        })
        (mkClient config.site.apps.immich {
          client_secret = "$argon2id$v=19$m=65536,t=3,p=4$MZZGRuALuFh6qmXYhBFRTg$27qX6xv264Cs6cuj18afQa1oc4ddt/X+ndYBkDVcMVU";
          redirect_paths = [ "auth/login" "user-settings" ];
          redirect_uris = [ "app.immich:///oauth-callback" ];
          response_types = [ "code" ];
          require_pkce = false;
          pkce_challenge_method = "";
          token_endpoint_auth_method = "client_secret_post";
        })
        (mkClient config.site.apps.jellyfin {
          client_secret = "$argon2id$v=19$m=65536,t=3,p=4$LuRHBAoKS3llgeNibFAJCg$fqaNlYvfRKiGdbVUOi89pXeWQwe5pStzNhrvmvvJrWc";
          redirect_paths = [ "sso/OID/redirect/authelia" ];
          authorization_policy = "one_factor";
          token_endpoint_auth_method = "client_secret_post";
        })
        (mkClient config.site.apps.mealie {
          client_secret = "$argon2id$v=19$m=65536,t=3,p=4$hTubW+z8HklfQlm2mi8oPA$cFVnkx8aYkDkPlSJUcHo5F88vCfN/ija/U44sEqOa64";
          authorization_policy = "one_factor";
          redirect_paths = [ "login" ];
          redirect_uris = [ "http://localhost:${toString config.site.apps.mealie.port}/login" ];
        })
        (mkClient config.site.apps.memos {
          client_secret = "$argon2id$v=19$m=65536,t=3,p=4$5SHxB5qqWhPiYFeZ/cUXQQ$u1lemwNPR6FCopfiR65/jAt0DOfa5GXeKd/YqkD8l7M";
          redirect_paths = [ "auth/callback" ];
          require_pkce = false;
          pkce_challenge_method = "";
          token_endpoint_auth_method = "client_secret_post";
        })
        (mkClient config.site.apps.paperless {
          client_secret = "$argon2id$v=19$m=65536,t=3,p=4$eqYYBvna/cLi1FZ8nE+AVg$6fZX2RlCRTgJwBAR1fLwq2fCytjSheS5AJ0uDB9Rkwk";
          redirect_paths = [ "accounts/oidc/authelia/login/callback/" ];
        })
        (mkClient config.site.apps.sftpgo {
          authorization_policy = "one_factor";
          client_secret = "$argon2id$v=19$m=65536,t=3,p=4$XY2jSGxOVxEMvFvJ4hQ1Fg$hZah2TkuBoQrlJi8wiO5oyMGh3y09nc1CPr9UHbe/7k";
          claims_policy = "sftpgo";
          redirect_paths = [ "web/oidc/redirect" "web/oauth2/redirect" ];
        })
        (mkClient config.site.apps.vikunja {
          client_secret = "$argon2id$v=19$m=65536,t=3,p=4$zRMdh029w57vBVKYJUbrOA$XpthqZlqEa6neEoIffR8wHEt++KuMykATd/tte//4II";
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

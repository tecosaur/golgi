{ config, lib, pkgs, ... }:

let
  immich-domain = "${config.site.apps.immich.subdomain}.${config.site.domain}";
  immich-data = "/data/immich";
  immich-oidc-secret-template = "#=OIDC_CLIENT_SECRET=#";
  immich-secret-conf-dir = "/run/immich-conf";
in {
  site.apps.immich.enabled = true;

  age.secrets.immich-oidc = {
    owner = "immich";
    group = "users";
    file = ../secrets/immich-oidc-secret.age;
  };

  services.immich = {
    enable = true;
    openFirewall = false;
    host = "0.0.0.0";
    port = config.site.apps.immich.port;
    mediaLocation = immich-data;
    settings = {
      oauth = {
        enabled = true;
        autoLaunch = true;
        autoRegister = true;
        buttonText = "Login with OAuth";
        clientId = "immich";
        clientSecret = immich-oidc-secret-template;
        defaultStorageQuota = 0;
        issuerUrl = "https://${config.site.apps.authelia.subdomain}.${config.site.domain}/.well-known/openid-configuration";
        scope = "openid email profile";
        signingAlgorithm = "RS256";
        profileSigningAlgorithm = "none";
        storageLabelClaim = "preferred_username";
        storageQuotaClaim = "immich_quota";
      };
      passwordLogin = {
        enabled = false;
      };
      server = {
        externalDomain = "https://${immich-domain}";
      };
      storageTemplate = {
        enabled = true;
        hashVerificationEnabled = true;
        template = "{{#if album}}{{{album}}}{{else}}Unsorted{{/if}}/{{y}}/{{MM}}-{{MMM}}/{{y}}-{{MM}}-{{dd}}-{{filename}}";
      };
      machineLearning = {
        clip = {
          enabled = true;
          modelName = "ViT-B-16-SigLIP2__webli";
        };
      };
      notifications.smtp = {
        enabled = true;
        from = "services.immich@tecosaur.net";
        replyTo = "contact.immich@tecosaur.net";
        transport = {
          ignoreCert = false;
          host = "smtp.fastmail.com";
          port = 587;
          username = "tec@tecosaur.net";
          password = "";
        };
      };
    };
    environment = {
      IMMICH_CONFIG_FILE = lib.mkForce "${immich-secret-conf-dir}/immich.json";
    };
    machine-learning = {
      enable = true;
      # environment = {
      #   HSA_OVERRIDE_GFX_VERSION = "11.0.0";
      #   HSA_USE_SVM = "0";
      #   MACHINE_LEARNING_DEVICE_IDS = "0";
      # };
    };
    accelerationDevices = null;
  };

  systemd.services.immich-server = {
    preStart = let
      refConfig = (pkgs.formats.json { }).generate "immich.json" config.services.immich.settings;
      newConfig = "${immich-secret-conf-dir}/immich.json";
      replaceSecretBin = "${pkgs.replace-secret}/bin/replace-secret";
    in ''
    umask 077
    cp -f '${refConfig}' '${newConfig}'
    chmod u+w '${newConfig}'
    ${replaceSecretBin} '${immich-oidc-secret-template}' '${config.age.secrets.immich-oidc.path}' '${newConfig}'
    '';
  };

  # FIXME: Workaround for <https://github.com/NixOS/nixpkgs/issues/418799>
  users.users.immich = {
    home = "/var/lib/immich";
    createHome = true;
  };

  systemd.tmpfiles.rules = [
    "d ${immich-data} 0750 immich immich"
    "d ${immich-secret-conf-dir} 0700 immich immich"
  ];

  services.caddy.virtualHosts."${immich-domain}".extraConfig =
    ''reverse_proxy :${toString config.site.apps.immich.port}'';
}

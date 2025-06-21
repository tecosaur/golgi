{ config, lib, pkgs, ... }:

let
  immich-domain = "${config.site.apps.immich.subdomain}.${config.site.domain}";
in {
  site.apps.immich.enabled = true;

  services.immich = {
    enable = true;
    openFirewall = false;
    host = "0.0.0.0";
    port = config.site.apps.immich.port;
    mediaLocation = "/data/immich";
    settings = {
      oauth = {
        enabled = true;
        autoLaunch = true;
        autoRegister = true;
        buttonText = "Login with OAuth";
        clientId = "immich";
        clientSecret = "#= urgh =#";
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

  services.caddy.virtualHosts."${immich-domain}".extraConfig =
    ''reverse_proxy :${toString config.site.apps.immich.port}'';
}

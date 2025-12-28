{ config, lib, pkgs, ... }:

let
  immich-domain = "${config.site.apps.immich.subdomain}.${config.site.domain}";
  immich-data = "/data/immich";
in {
  site.apps.immich.enabled = true;

  age.secrets = {
    immich-oidc = {
      owner = "immich";
      group = "users";
      file = ../secrets/immich-oidc-secret.age;
    };
    immich-smtp = {
      owner = "immich";
      file = ../secrets/fastmail.age;
    };
  };

  services.immich = {
    enable = true;
    group = "users";
    openFirewall = false;
    host = "0.0.0.0";
    port = config.site.apps.immich.port;
    mediaLocation = immich-data;
    database.enableVectors = false; # No more pgvecto-rs
    settings = {
      oauth = {
        enabled = true;
        autoLaunch = true;
        autoRegister = true;
        buttonText = "Login";
        clientId = "immich";
        clientSecret._secret = config.age.secrets.immich-oidc.path;
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
        ocr.modelName = "EN__PP-OCRv5_mobile";
        facialRecognition.minFaces = 8;
      };
      notifications.smtp = {
        enabled = true;
        from = "services.immich@${config.site.domain}";
        replyTo = "contact.immich@${config.site.domain}";
        transport = {
          ignoreCert = false;
          host = config.site.email.server;
          port = config.site.email.port;
          username = config.site.email.username;
          password._secret = config.age.secrets.immich-smtp.path;
        };
      };
    };
    machine-learning = {
      enable = true;
      environment = {
        # HSA_OVERRIDE_GFX_VERSION = "11.0.0";
        # HSA_USE_SVM = "0";
        # MACHINE_LEARNING_DEVICE_IDS = "0";
        MACHINE_LEARNING_MODEL_TTL = "0"; # Never expire
        MACHINE_LEARNING_PRELOAD__CLIP__VISUAL =
          let clip = config.services.immich.settings.machineLearning.clip; in
          if clip.enabled then clip.modelName else "";
        MACHINE_LEARNING_PRELOAD__CLIP__TEXTUAL =
          let clip = config.services.immich.settings.machineLearning.clip; in
          if clip.enabled then clip.modelName else "";
      };
    };
    accelerationDevices = null;
  };

  systemd.services.immich-server = {
    serviceConfig.UMask = lib.mkForce "0027";
  };

  # FIXME: Workaround for <https://github.com/NixOS/nixpkgs/issues/418799>
  users.users.immich = {
    home = "/var/lib/immich";
    createHome = true;
  };

  systemd.tmpfiles.rules = [
    "d ${immich-data} 0750 immich users"
  ];

  services.caddy.virtualHosts."${immich-domain}".extraConfig =
    ''reverse_proxy :${toString config.site.apps.immich.port}'';
}

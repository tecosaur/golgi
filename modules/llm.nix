{ config, lib, pkgs, ... }:

let
  llm = config.site.apps.llm;
  llm-domain = "${llm.subdomain}.${config.site.domain}";
  pool = llm.proxy ++ lib.optional llm.local ":${toString llm.port}";
  lb-policy = if llm.local-fallback || lib.length pool < 2 then "first" else "round_robin";
  pool-proxy =
    ''
    reverse_proxy {
        to ${lib.concatStringsSep " " pool}
        lb_policy ${lb-policy}
        health_uri /health
        health_interval 10s
        health_timeout 5s
        health_passes 1
        health_fails 1
        lb_try_duration 5s
    }'';
  gpu-environment = {
    GGML_VK_VISIBLE_DEVICES = "0";
    GGML_VK_PREFER_HOST_MEMORY = "1";
    RADV_PERFTEST = "nogttspill";
    HSA_OVERRIDE_GFX_VERSION = "11.0.0";
  };
  proxy-config = lib.optionalString llm.embedding.enable
    ''
    handle /v1/embeddings {
        reverse_proxy :${toString llm.embedding.port}
    }
    '' + lib.optionalString (pool != [ ])
    ''
    handle {
        ${pool-proxy}
    }'';
in lib.mkMerge [
  {
    assertions = [
      { assertion = llm.local || llm.proxy != [ ] || llm.embedding.enable;
        message = "site.apps.llm has no endpoints: enable `local`, `embedding`, or populate `proxy`.";
      }
    ];

    site.apps.llm.enabled = true;

    age.secrets.llm-api-key = {
      owner = "caddy";
      file = ../secrets/passwords/llm-api-key.age;
    };

    services.caddy.virtualHosts."${llm-domain}".extraConfig =
      ''
      @authenticated header Authorization "Bearer {file.{$LLM_API_KEY_PATH}}"
      handle @authenticated {
          ${proxy-config}
      }
      handle {
          import auth
          ${proxy-config}
      }
      '';

    systemd.services.caddy.environment.LLM_API_KEY_PATH = config.age.secrets.llm-api-key.path;
  }

  (lib.mkIf (llm.local || llm.embedding.enable) {
    boot = {
      kernelParams = [ "iommu=pt" ];
      extraModprobeConfig = "options ttm pages_limit=5767168 page_pool_size=5767168";
    };

    users.users.llm = {
      isSystemUser = true;
      home = "/var/lib/llama-cpp";
      createHome = true;
      group = "llm";
      extraGroups = [ "users" "video" "render" ];
    };

    users.groups.llm = {};
  })

  (lib.mkIf llm.local {
    services.llama-cpp = {
      enable = true;
      package = pkgs.llama-cpp-vulkan;
      settings = {
        host = "127.0.0.1";
        port = llm.port;
        hf-repo = "unsloth/gemma-4-E4B-it-qat-GGUF:UD-Q4_K_XL";
        alias = "'Gemma 4:E4B'";
        reasoning = "off";
        spec-type = "draft-mtp";
        spec-draft-n-max = 2;
        jinja = true;
        temp = 1.0;
        top-p = 0.95;
        min-p = 0.0;
        top-k = 64;
        n-gpu-layers = 99;
        flash-attn = "on";
        cache-ram = 1024;
        no-mmap = true;
        parallel = 1;
        ctx-size = 32768;
        ctx-checkpoints = 2;
      };
    };

    systemd.services.llama-cpp = {
      environment = gpu-environment;
      serviceConfig = {
        User = "llm";
        Group = "llm";
        DynamicUser = lib.mkForce false;
        StateDirectory = "llama-cpp";
        MemoryAccounting = true;
        MemoryMax = "20G";
      };
    };
  })

  (lib.mkIf llm.embedding.enable {
    # `services.llama-cpp` only defines a single instance, so the embedding
    # server is its own unit.
    systemd.services.llama-cpp-embedding = {
      description = "llama.cpp embedding server";
      wants = [ "network.target" ];
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];
      environment = gpu-environment // { LLAMA_CACHE = "/var/cache/llama-cpp"; };
      serviceConfig = {
        ExecStart = lib.escapeShellArgs [
          (lib.getExe' pkgs.llama-cpp-vulkan "llama-server")
          "--host" "127.0.0.1"
          "--port" (toString llm.embedding.port)
          "--hf-repo" "jinaai/jina-embeddings-v5-text-nano-retrieval-GGUF:F16"
          "--alias" "embedding"
          "--embeddings"
          "--pooling" "last"
          # A non-causal encoder processes an input in one batch, so the batch
          # sizes cap how much can be embedded at once.
          "--batch-size" "8192"
          "--ubatch-size" "8192"
          "--n-gpu-layers" "99"
          "--no-mmap"
          "--parallel" "1"
        ];
        Restart = "on-failure";
        RestartSec = 300;
        User = "llm";
        Group = "llm";
        StateDirectory = "llama-cpp";
        CacheDirectory = "llama-cpp";
        WorkingDirectory = "/var/lib/llama-cpp";
        MemoryAccounting = true;
        MemoryMax = "4G";
      };
    };
  })
]

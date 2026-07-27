{ config, lib, pkgs, ... }:

let
  llm-domain = "${config.site.apps.llm.subdomain}.${config.site.domain}";
in {
  site.apps.llm.enabled = true;

  boot = {
    kernelParams = [ "iommu=pt" ];
    extraModprobeConfig = "options ttm pages_limit=5767168 page_pool_size=5767168";
  };

  age.secrets.llm-api-key = {
    owner = "caddy";
    file = ../secrets/llm-api-key.age;
  };

  users.users.llm = {
    isSystemUser = true;
    home = "/var/lib/llama-cpp";
    createHome = true;
    group = "llm";
    extraGroups = [ "users" "video" "render" ];
  };

  users.groups.llm = {};

  services.llama-cpp = {
    enable = true;
    package = pkgs.llama-cpp-vulkan;
    settings = {
      host = "127.0.0.1";
      port = config.site.apps.llm.port;
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
      swa-full = true;
      cache-ram = 1024;
      no-mmap = true;
      parallel = 1;
      ctx-size = 32768;
      ctx-checkpoints = 2;
    };
  };

  systemd.services.llama-cpp = {
    environment = {
      GGML_VK_VISIBLE_DEVICES = "0";
      GGML_VK_PREFER_HOST_MEMORY = "1";
    };
    serviceConfig = {
      User = "llm";
      Group = "llm";
      DynamicUser = lib.mkForce false;
      StateDirectory = "llama-cpp";
      MemoryAccounting = true;
      MemoryMax = "20G";
    };
  };

  services.caddy.virtualHosts."${llm-domain}".extraConfig =
    ''
    @authenticated header Authorization "Bearer {file.{$LLM_API_KEY_PATH}}"
    route {
        handle @authenticated {
            reverse_proxy :${toString config.site.apps.llm.port}
        }
        handle {
            import auth
            reverse_proxy :${toString config.site.apps.llm.port}
        }
    }
    '';

  systemd.services.caddy.environment.LLM_API_KEY_PATH = config.age.secrets.llm-api-key.path;
}

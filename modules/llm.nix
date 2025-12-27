{ config, lib, pkgs, ... }:

let
  llm-domain = "${config.site.apps.llm.subdomain}.${config.site.domain}";
  hf-model = "unsloth/Qwen3-VL-30B-A3B-Instruct-GGUF:UD-Q3_K_XL";
  llama-model-args = "--jinja --top-p 0.8 --min-p 0.0 --top-k 20 --temp 0.7 --presence-penalty 1.5";
  llama-perf-args = "--n-gpu-layers 99 --flash-attn on --cache-type-k q8_0 --cache-type-v q8_0 --ctx-size 12288";
  llama-cpp = (pkgs.llama-cpp.override {
    vulkanSupport = true;
  }).overrideAttrs( old: rec {
    version = "7079";
    src = pkgs.fetchFromGitHub {
      owner = "ggml-org";
      repo = "llama.cpp";
      tag = "b7079";
      hash = "sha256-qZn5ABpFp1RhJ34bZU+EAyiuuv5XjVZivdkjFXCVXCU=";
      leaveDotGit = true;
      postFetch = ''
      git -C "$out" rev-parse --short HEAD > $out/COMMIT
      find "$out" -name .git -print0 | xargs -0 rm -rf
    '';
    };
  });
in {
  site.apps.llm.enabled = true;

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
    package = llama-cpp;
    model = "/"; # We override the ExecStart below
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
      ExecStart = lib.mkForce "${llama-cpp}/bin/llama-server --host 127.0.0.1 --port ${toString config.site.apps.llm.port} -hf ${hf-model} ${llama-perf-args} ${llama-model-args}";
      StateDirectory = "llama-cpp";
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

{ config, lib, ... }:

{
  options.globals = {
    domain = lib.mkOption {
      type = lib.types.str;
      default = "example.com";
      description = "Global domain for the server";
    };
    auth-domain = lib.mkOption {
      type = lib.types.str;
      default = "auth.example.com";
      description = "OAuth2/OICD domain";
    };
    cloudflare-bypass = lib.mkOption {
      type = lib.types.str;
      default = config.globals.domain;
      description = "Domain to use for bypassing Cloudflare (e.g. for SSH).";
    };
  };
  config.globals = {
    domain = "tecosaur.net";
    auth-domain = "auth.${config.globals.domain}";
    cloudflare-bypass = "ssh.${config.globals.domain}";
  };
}

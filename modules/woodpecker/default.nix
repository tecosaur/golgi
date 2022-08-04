{ config, lib, pkgs, ... }:

{
  imports = [
    ./woodpecker-server.nix
    ./woodpecker-agent.nix
  ];

  age.secrets.woodpecker-client-id = {
    owner = "woodpecker-server";
    group = "users";
    file = ../../secrets/woodpecker-client-id.age;
  };

  age.secrets.woodpecker-client-secret = {
    owner = "woodpecker-server";
    group = "users";
    file = ../../secrets/woodpecker-client-secret.age;
  };

  age.secrets.woodpecker-agent-secret = {
    owner = "woodpecker-server";
    group = "users";
    file = ../../secrets/woodpecker-agent-secret.age;
  };

  services.woodpecker-server = {
    enable = true;
    rootUrl = "https://ci.tecosaur.net";
    httpPort = 3030;
    database = {
      type = "postgres";
    };
    giteaClientIdFile = config.age.secrets.woodpecker-client-id.path;
    giteaClientSecretFile = config.age.secrets.woodpecker-client-secret.path;
    agentSecretFile = config.age.secrets.woodpecker-agent-secret.path;
  };

  services.woodpecker-agent = {
    enable = true;
  };
}

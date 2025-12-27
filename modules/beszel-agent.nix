{ config, lib, pkgs, ... }:

{
  age.secrets.beszel-token = {
    owner = "beszel-agent";
    file = ../secrets/beszel-token.age;
  };

  services.beszel.agent = {
    enable = true;
    openFirewall = true;
    environment = {
      HUB_URL = "https://${config.site.apps.beszel.subdomain}.${config.site.domain}";
      KEY = config.site.apps.beszel.publicKey;
      TOKEN_FILE = config.age.secrets.beszel-token.path;
      PORT = toString config.site.apps.beszel.agent-port;
      EXTRA_FILESYSTEMS = lib.concatStringsSep "," config.site.apps.beszel.extra-filesystems;
    };
  };

  systemd.services.beszel-agent = {
    path = [ pkgs.smartmontools ] ++ (
      if builtins.elem "kvm-amd" config.boot.initrd.kernelModules then
        [ pkgs.rocmPackages.rocm-smi ]
      else []);
    serviceConfig = {
      # SMART monitoring.
      # REVIEW after <https://github.com/NixOS/nixpkgs/pull/460730> is merged.
      AmbientCapabilities = [ "CAP_SYS_RAWIO" "CAP_SYS_ADMIN" ];
      CapabilityBoundingSet = [ "CAP_SYS_RAWIO" "CAP_SYS_ADMIN" ];
      DeviceAllow = [ "/dev/sd* r" "/dev/nvme* r" ];
      SupplementaryGroups = [ "disk" ];
      NoNewPrivileges = lib.mkForce false;
      PrivateDevices = false;
      PrivateUsers = lib.mkForce false;
      # Systemd service monitoring.
      # REVIEW after <https://github.com/NixOS/nixpkgs/pull/461327> is merged.
      BindReadOnlyPaths = [
        "/var/run/systemd/private"
        "/var/run/dbus/system_bus_socket"
      ];
    };
  };

  services.udev.extraRules = ''
    # Change NVMe devices to disk group ownership for S.M.A.R.T. monitoring
    KERNEL=="nvme[0-9]*", GROUP="disk", MODE="0660"
  '';

  users.users.beszel-agent = {
    isSystemUser = true;
    group = "beszel-agent";
  };

  users.groups.beszel-agent = { };
}

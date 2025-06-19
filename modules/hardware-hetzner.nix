{ config, pkgs, modulesPath, ... }:

{
  nixpkgs.hostPlatform = "x86_64-linux";
  system.stateVersion = "23.05";

  boot = {
    initrd = {
      availableKernelModules = [ "ahci" "xhci_pci" "virtio_pci" "sd_mod" "sr_mod" ];
      kernelModules = [ "nvme" ];
    };
    kernel.sysctl = {
      "vm.swappiness" = 60;
      "net.core.rmem_max" = 8388608;
      "net.core.wmem_max" = 8388608;
    };
    kernelParams = [
      "console=tty1"
      "console=ttyS0,115200"
    ];
    extraModulePackages = [ ];
    loader.grub = {
      enable = true;
      device = "/dev/sda";
    };
  };

  fileSystems."/" =
    {
      device = "/dev/disk/by-label/NIXOS";
      fsType = "btrfs";
      options = [ "subvol=@rootfs" "noatime" "compress=zstd" ];
    };

  fileSystems."/nix" =
    {
      device = "/dev/disk/by-label/NIXOS";
      fsType = "btrfs";
      options = [ "subvol=@nix" "noatime" "compress=zstd" ];
    };


  fileSystems."/boot" =
    {
      device = "/dev/disk/by-label/NIXOS";
      fsType = "btrfs";
      options = [ "subvol=@boot" "noatime" "compress=zstd" ];
    };

  fileSystems."/swap" = {
    device = "/dev/disk/by-label/NIXOS";
    fsType = "btrfs";
    options = [ "subvol=@swap" "noatime" "compress=zstd:1" ];
  };

  systemd.services = {
    create-swapfile = {
      serviceConfig.Type = "oneshot";
      wantedBy = [ "swap-swapfile.swap" ];
      script = ''
        ${pkgs.coreutils}/bin/truncate -s 0 /swap/swapfile
        ${pkgs.e2fsprogs}/bin/chattr +C /swap/swapfile
        ${pkgs.btrfs-progs}/bin/btrfs property set /swap/swapfile compression none
      '';
    };
  };

  swapDevices = [{
    device = "/swap/swapfile";
    size = (1024 * 2);
  }];

  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
  ];

  networking = {
    enableIPv6 = true;
    usePredictableInterfaceNames = true;
    useNetworkd = true;
    useDHCP = true;
    dhcpcd.enable = false;
    timeServers = [
      "ntp1.hetzner.de"
      "ntp2.hetzner.com"
      "ntp3.hetzner.net"
    ];
  };

  systemd.network = {
    enable = true;
    wait-online.ignoredInterfaces =
      [ "lo" ] ++ (if config.services.tailscale.enable then [ "tailscale0" ] else []);
    networks."10-uplink" = {
      matchConfig.Name = "enp1s0";
      addresses = [ { Address = "${config.site.server.ipv6}/64"; } ];
      domains = [ config.site.domain ];
      routes = [ { Gateway = "fe80::1"; } ];
      dns = [ "2606:4700:4700::1111" # Cloudflare
              "2606:4700:4700::1001" ];
      networkConfig = {
        DHCP = "ipv4";
        IPv6AcceptRA = "yes";
      };
    };
  };
}

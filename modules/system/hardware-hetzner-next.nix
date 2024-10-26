{ config, pkgs, modulesPath, ... }:

let
  IPv4addr = "5.161.98.27";
  IPv6addr = "2a01:4ff:f0:cc83::/64";
in {
  boot = {
    initrd = {
      availableKernelModules = [ "ahci" "xhci_pci" "virtio_pci" "sd_mod" "sr_mod" ];
      kernelModules = [ "nvme" ];
    };
    kernel.sysctl."vm.swappiness" = 10;
    kernelParams = [
      "console=tty1"
      "console=ttyS0,115200"
    ];
    extraModulePackages = [ ];
    loader.grub = {
      enable = true;
      device = "/dev/sda";
      efiSupport = true;
      efiInstallAsRemovable = true;
    };
  };

  networking = {
    enableIPv6 = true;
    usePredictableInterfaceNames = true;
    useNetworkd = true;
    useDHCP = false;
    dhcpcd.enable = false;
    timeServers = [
      "ntp1.hetzner.de"
      "ntp2.hetzner.com"
      "ntp3.hetzner.net"
    ];
  };

  systemd.network = {
    enable = true;
    wait-online.ignoredInterfaces = [ "lo" ];
    networks."10-uplink" = {
      matchConfig.Name = "enp1s0";
      address = [ IPv6addr ];
      gateway = [ "fe80::1" ];
      domains = [ config.site.domain ];
      networkConfig = {
        DHCP = "ipv4";
        IPForward = true;
        LinkLocalAddressing = "ipv6";
        IPv6AcceptRA = true;
        DNS = [ "2606:4700:4700::1111" # Cloudflare
                "2606:4700:4700::1001" ];
      };
    };
  };

  boot.initrd.systemd.network.networks."10-uplink" = config.systemd.network.networks."10-uplink";

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
    options = [ "subvol=@swap" "noatime" "compress=zstd" ];
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
}

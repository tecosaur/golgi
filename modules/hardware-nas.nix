{ config, pkgs, modulesPath, ... }:

{
  nixpkgs.hostPlatform = "x86_64-linux";
  system.stateVersion = "25.05";

  boot = {
    initrd = {
      availableKernelModules = [ "xhci_pci" "thunderbolt" "ahci" "nvme" "usb_storage" "sd_mod" "tpm_crb" "tpm_tis" "igc" ];
      kernelModules = [ "kvm-amd" ];
      clevis = { # Requires the kernel modules: tpm_crb, tpm_tis, and igc (Intel NIC)
        enable = true;
        useTang = true;
        devices."${config.fileSystems."/data".device}".secretFile = ../secrets/clevis-nucleus.jwe;
      };
      network.enable = true;
    };
    kernelPackages = pkgs.linuxPackages_latest;
    kernel.sysctl = {
      "vm.swappiness" = 40;
      "net.core.rmem_max" = 8388608;
      "net.core.wmem_max" = 8388608;
    };
    extraModulePackages = [ ];
    loader.systemd-boot.enable = true;
    loader.efi.canTouchEfiVariables = true;
  };

  hardware.cpu.amd.updateMicrocode = true;
  hardware.enableRedistributableFirmware = true;

  fileSystems."/" =
    {
      device = "/dev/disk/by-partlabel/nixos";
      fsType = "bcachefs";
      # options = [ "X-mount.subdir=root" ];
    };

  # fileSystems."/nix" =
  #   {
  #     device = "/dev/disk/by-partlabel/nixos";
  #     fsType = "bcachefs";
  #     options = [ "X-mount.subdir=nix" ];
  #   };

  # fileSystems."/var/log" =
  #   {
  #     device = "/dev/disk/by-partlabel/nixos";
  #     fsType = "bcachefs";
  #     options = [ "X-mount.subdir=log" ];
  #   };

  fileSystems."/boot" = {
    device = "/dev/disk/by-partlabel/ESP";
    fsType = "vfat";
    options = [
      "fmask=0022"
      "dmask=0022"
    ];
  };

  fileSystems."/data" = {
    device = "/dev/disk/by-label/Data";
    fsType = "bcachefs";
    neededForBoot = true; # See <https://github.com/NixOS/nixpkgs/issues/357755>
  };

  swapDevices = [{
    device = "/dev/disk/by-partlabel/swap";
  }];

  networking = {
    enableIPv6 = true;
    usePredictableInterfaceNames = true;
    useNetworkd = true;
    useDHCP = true;
    dhcpcd.enable = false;
    firewall.allowedUDPPorts = [ 5353 ]; # mDNS
  };

  systemd.network = {
    enable = true;
    wait-online.ignoredInterfaces =
      [ "lo" ] ++ (if config.services.tailscale.enable then [ "tailscale0" ] else []);
    networks."10-uplink" = {
      matchConfig.Name = "enp101s0";
      # domains = [ config.site.domain ];
      routes = [ { Gateway = "_ipv6ra"; } ];
      networkConfig = {
        DHCP = "yes";
        IPv6AcceptRA = true;
        MulticastDNS = true;
      };
      linkConfig.Multicast = true;
      ipv6AcceptRAConfig = {
        Token = "eui64";
        UseDNS = true;
      };
    };
  };
}

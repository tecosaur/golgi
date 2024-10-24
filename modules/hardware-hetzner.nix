{ config, pkgs, modulesPath, ... }:

{
  networking.networkmanager.enable = true;

  boot = {
    initrd = {
      availableKernelModules = [ "ahci" "xhci_pci" "virtio_pci" "sd_mod" "sr_mod" ];
      kernelModules = [ ];
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
    options = [ "subvol=@swap" "noatime" ];
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

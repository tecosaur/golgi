#!/usr/bin/env nix-shell
#!nix-shell -i bash -p bash gptfdisk util-linux btrfs-progs
set -ex

if [ "$EUID" -ne 0 ]
  then echo "Please run as root for mount permissions!"
  exit
fi

BTRFS_OPTS="compress=zstd,noatime"
MNT="/mnt"
TARGET="/dev/sda"

# GPT labels
# /dev/sda1 -> BIOS boot
# /dev/sda2 -> BTRFS partition, with
#   @rootfs mounted at /
#   @nix    mounted at /nix
#   @boot   mounted at /boot
#   @swap   mounted at /swap

# Mount everything at /mnt to install the system

sgdisk --zap-all "${TARGET}"
sgdisk -a1 -n1:2048:4095 -t1:EF02 "${TARGET}"
sgdisk     -n2:0:0       -t2:8300 "${TARGET}"

fdisk -l "${TARGET}"

mkfs.btrfs -f -L NIXOS "${TARGET}2"

mkdir -p "${MNT}"
umount -R "${MNT}" || :
mount "${TARGET}2" "${MNT}"
btrfs subvolume create "${MNT}"/@rootfs
btrfs subvolume create "${MNT}"/@nix
btrfs subvolume create "${MNT}"/@boot
btrfs subvolume create "${MNT}"/@swap
umount "${MNT}"

mount -o "$BTRFS_OPTS,subvol=@rootfs" "${TARGET}2" "${MNT}"
mkdir "${MNT}"/{nix,boot,swap}
mount -o "$BTRFS_OPTS,subvol=@nix" "${TARGET}2" "${MNT}"/nix
mount -o "$BTRFS_OPTS,subvol=@swap" "${TARGET}2" "${MNT}"/swap
mount -o "$BTRFS_OPTS,subvol=@boot" "${TARGET}2" "${MNT}"/boot

findmnt -R --target "${MNT}"

# .#golgi is our hostname defined by our flake
nix-shell -p nixUnstable -p git --run "nixos-install --root ${MNT} --flake .#golgi"
umount -R /mnt

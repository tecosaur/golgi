#!/usr/bin/env nix-shell
#!nix-shell -i bash -p bash bcachefs-tools btrfs-progs curl clevis git gptfdisk gum util-linux

set -euo pipefail

if [ "$EUID" -ne 0 ]
  then echo "Please run as root for mount permissions!"
  exit 2
fi

scriptdir="$(dirname "$(realpath "$0")")"

if [ ! -d "$scriptdir/.git" ]
  then echo "Please clone from git repository!"
  exit 3
fi

function self_update() {
    local old_rev="$(git -C "$scriptdir" rev-parse HEAD)"
    gum spin -s line --spinner.foreground=185 --title="Checking for updates" -- git -C "$scriptdir" pull --rebase
    if [ "$(git -C "$scriptdir" rev-parse HEAD)" != "$old_rev" ] && \
        ! git -C "$scriptdir" diff --quiet "$old_rev"..HEAD -- "$(realpath "$0")"; then
        gum style --foreground=221 " New version available, restarting installer..."
        exec env INHIBIT_UPDATE_CHECK=1 "$0" "$@"
    fi
}

if [ -z "${INHIBIT_UPDATE_CHECK:-}" ]; then
    self_update
fi

# 
# common vars/utils

export GUM_CHOOSE_CURSOR_FOREGROUND="72"
export GUM_CHOOSE_HEADER_FOREGROUND="37"
export GUM_CHOOSE_SELECTED_FOREGROUND="72"
export GUM_CONFIRM_PROMPT_FOREGROUND="37"
export GUM_CONFIRM_SELECTED_BACKGROUND="72"
export GUM_FILTER_HEADER_FOREGROUND="37"
export GUM_FILTER_INDICATOR_FOREGROUND="72"
export GUM_FILTER_SELECTED_PREFIX_FOREGROUND="72"
export GUM_INPUT_CURSOR_FOREGROUND="72"
export GUM_INPUT_HEADER_FOREGROUND="72"
export GUM_SPIN_SPINNER_FOREGROUND="72"
export GUM_SPIN_SPINNER="line"
export BORDER_FOREGROUND="72"
export PADDING="0 1"

MNT="/mnt"
export MNT

sysname=""
bootdrive=""
data_drives_warm=()
data_drives_hot=()

function unassigned_devices() {
    lsblk -nd -o PATH,SIZE,MODEL --filter='!MOUNTPOINTS && (TRAN == "nvme" || TRAN == "sata")' | while IFS= read -r line; do
        printf '%s:' $bootdrive "${data_drives_warm[@]}" "${data_drives_hot[@]}" | grep -q "$(echo  "$line" | cut -d' ' -f1)" || echo "$line"
    done
}

function pick_unassigned_device() {
    local devtable=$(unassigned_devices)
    echo "$devtable" | gum filter --header=" Select $1" --height="$((4 + $(echo "$devtable" | wc -l)))" "${@:2}" | cut -d' ' -f1
}

function drive_kind() {
    [[ "$(lsblk -dn -o rota "$1")" == "0" ]] && echo "ssd" || echo "hdd"
}

function drive_partition_count() {
    lsblk -n "$1" --filter='TYPE == "part"' | wc -l
}

function generate_ssh_key() {
    gum style --border="thick" "SSH Keys"
    mkdir -p "${MNT}/etc/ssh"
    ssh-keygen -q -t ed25519 -N '' -C "root@${sysname}" -f "${MNT}/etc/ssh/ssh_host_ed25519_key"
    chmod 600 "${MNT}/etc/ssh/ssh_host_ed25519_key"
    gum join "$(gum style --foreground=72 "Public key:")" "$(cat "${MNT}/etc/ssh/ssh_host_ed25519_key.pub")"
    gum confirm --affirmative="Pull" --negative="Skip" "Pull git repository to fetch updated secrets?" &&
        gum spin --title="Pulling..." --show-stdout -- git pull --rebase -C "$scriptdir" || true
}

function nix_disable_nonessential_modules() {
    local modules nonessential_modules
    mapfile -t modules < <({
        find "$scriptdir/modules" -mindepth 1 -maxdepth 1 -type f -name '*.nix' -printf '%f\n' | sed 's/\.nix$//'
        find "$scriptdir/modules" -mindepth 1 -maxdepth 1 -type d -printf '%f\n'
      } | sort -u)
    nonessential_modules=()
    for mod in "${modules[@]}"; do
        if [[ "$mod" != system ]] && [[ ! "$mod" == hardware-* ]]; then
            nonessential_modules+=("$mod")
        fi
    done
    cp "$scriptdir/flake.nix" "$scriptdir/flake.nix.bak"
    for mod in "${nonessential_modules[@]}"; do
        sed -ri "s|^(\s*)${mod}(\s*)$|\1# ${mod}\2|" "$scriptdir/flake.nix"
    done
}

# 
# Btrfs

BTRFS_OPTS="compress=zstd,noatime"

function format_boot_btrfs() {
    sgdisk --zap-all "$1"
    sgdisk -a1 -n1:2048:4095 -t1:EF02 "$1"
    sgdisk     -n2:0:0       -t2:8300 "$1"

    [[ $1 == *nvme* ]] && partsep='p' || partsep=''

    wipefs -a -f "$1${partsep}1" "$1${partsep}2"

    mkfs.btrfs -f -L NIXOS "$1${partsep}2"

    mkdir -p "${MNT}"
    umount -R "${MNT}" || :
    mount "$1${partsep}2" "${MNT}"
    btrfs subvolume create "${MNT}"/@rootfs
    btrfs subvolume create "${MNT}"/@nix
    btrfs subvolume create "${MNT}"/@boot
    btrfs subvolume create "${MNT}"/@swap
    umount "${MNT}"

    mount -o "$BTRFS_OPTS,subvol=@rootfs" "$1${partsep}2" "${MNT}"
    mkdir "${MNT}"/{nix,boot,swap}
    mount -o "$BTRFS_OPTS,subvol=@nix" "$1${partsep}2" "${MNT}"/nix
    mount -o "$BTRFS_OPTS,subvol=@swap" "$1${partsep}2" "${MNT}"/swap
    mount -o "$BTRFS_OPTS,subvol=@boot" "$1${partsep}2" "${MNT}"/boot
}

export BTRFS_OPTS
export -f format_boot_btrfs

function interactive_format_boot_btrfs() {
    gum style --border="thick" "Boot drive"

    bootdrive="$(pick_unassigned_device "boot drive" --select-if-one)"
    gum join "$(gum style --foreground=72 "Boot drive:")" "$bootdrive"

    if [ "$(drive_partition_count "$bootdrive")" != "0" ]; then
       gum confirm --affirmative="Continue" --negative="Abort" "Overwrite $(drive_partition_count "$bootdrive") existing partition(s) on $bootdrive?" || exit 1
    fi

    gum spin --title="Formatting boot drive" -- bash -c "set -e; format_boot_btrfs $bootdrive"

    gum join --align=center --vertical \
        "$(gum style --foreground=37 "Boot Disk")" \
        "$(fdisk -l "$bootdrive" | gum style --bold=false  --border=rounded --border-foreground=37)"
    gum join --align=center --vertical \
        "$(gum style --foreground=37 "Boot Mounts")" \
        "$(findmnt -R --target "$MNT" | cut -c1-"$(($COLUMNS - 4))" | gum style --bold=false  --border=rounded --border-foreground=37)"
}

# 
# Bcachefs

bcachefs_root_opts=(
    --block_size=4096 --errors=fix_safe
    --fs_label=NixOS --label=root
    --compression=lz4 --discard # Assume flash storage
)

bcachefs_data_opts=(
    --block_size=4096 --errors=fix_safe
    --fs_label=Data --replicas=2
    --force # In case of existing partition(s)
)

bcachefs_drive_args=()

function format_boot_bcachefs() {
    mkdir -p "${MNT}"
    umount -R "${MNT}" || :

    sgdisk --zap-all "$1"
    sgdisk -a1 -n1:1M:+512M -t1:EF00 -c1:ESP \
               -n2:0:+"$2"  -t2:8300 -c2:nixos \
               -n3:0:0      -t3:8200 -c3:swap "$1"

    [[ $1 == *nvme* ]] && partsep='p' || partsep=''

    partprobe "$1" || :
    udevadm settle
    wipefs -a -f "$1${partsep}1" "$1${partsep}2" "$1${partsep}3"

    mkfs.vfat "$1${partsep}1"
    mkswap -L swap "$1${partsep}3"
    bcachefs format "${@:3}" "$1${partsep}2"

    mount "$1${partsep}2" "${MNT}"
    # TODO: Re-enable once the subvolume situation is better
    # mkdir -p "${MNT}"
    # umount -R "${MNT}" || :
    # mount "$1${partsep}2" "${MNT}"
    # bcachefs subvolume create "${MNT}/root"
    # bcachefs subvolume create "${MNT}/nix"
    # bcachefs subvolume create "${MNT}/log"
    # umount "${MNT}"

    # mount -o X-mount.subdir=root "$1${partsep}2" "${MNT}"
    # mkdir -p "${MNT}"/{boot,home,nix,var/log}
    # mount -o X-mount.subdir=nix "$1${partsep}2" "${MNT}/nix"
    # mount -o X-mount.subdir=log "$1${partsep}2" "${MNT}/var/log"

    mkdir -p "${MNT}"/boot # for while the above is commented out
    mount -o umask=0077 "$1${partsep}1" "${MNT}/boot"
}

export -f format_boot_bcachefs

function interactive_format_boot_bcachefs() {
    gum style --border="thick" "Boot drive"

    bootdrive="$(pick_unassigned_device "boot drive" --select-if-one)"
    gum join "$(gum style --foreground=72 "Boot drive:")" "$bootdrive"

    if [ "$(drive_partition_count "$bootdrive")" != "0" ]; then
       gum confirm --affirmative="Continue" --negative="Abort" "Overwrite $(drive_partition_count "$bootdrive") existing partition(s) on $bootdrive?" || exit 1
    fi

    local rootsize="$(gum input --prompt=" $(lsblk -nd -o SIZE "$bootdrive") availible> " --header=" Root partition size (rest is used for swap)" --placeholder="<n>G")"

    gum spin --title="Formatting boot drive" -- bash -c "set -e; format_boot_bcachefs $bootdrive $rootsize ${bcachefs_root_opts[@]}"

    gum join --align=center --vertical \
        "$(gum style --foreground=37 "Boot Disk")" \
        "$(fdisk -l "$bootdrive" | gum style --bold=false --border=rounded --border-foreground=37)"
    gum join --align=center --vertical \
        "$(gum style --foreground=37 "Boot Mounts")" \
        "$(findmnt -R --target "$MNT" | cut -c1-"$(($COLUMNS - 4))" | gum style --bold=false --border=rounded --border-foreground=37)"
}

declare -A drive_counters

function format_bcachefs_drive_args() {
    bcachefs_drive_args=()
    if [ -n "$data_password" ]; then
        bcachefs_drive_args+=(--encrypted)
    fi
    ((drive_counters['bg']=1))
    for dev in "${data_drives_warm[@]}"; do
        bcachefs_drive_args+=(
            --label="data.warm.$((drive_counters['bg']++))"
            --compression=zstd
        )
        if [[ "$(drive_kind "$dev")" == "ssd" ]]; then
            bcachefs_drive_args+=(--discard)
        fi
        bcachefs_drive_args+=("$dev")
    done
    ((drive_counters['fg']=1))
    for dev in "${data_drives_hot[@]}"; do
        bcachefs_drive_args+=(
            --label="data.hot.$((drive_counters['fg']++))"
            --compression=lz4
        )
        if [[ "$(drive_kind "$dev")" == "ssd" ]]; then
            bcachefs_drive_args+=(--discard)
        fi
        bcachefs_drive_args+=("$dev")
    done
    if [ -n "$data_drives_hot" ]; then
        bcachefs_drive_args+=(
            --foreground_target=data.hot
            --promote_target=data.hot
            --background_target=data.warm
        )
    fi
}

function interactive_set_data_drives() {
    gum style --border="thick" "Data drives"

    readarray -t data_drives_warm <<<"$(pick_unassigned_device "warm data drives" --no-limit)"
    gum join "$(gum style --foreground=72 "Warm data drives:")" \
        "$(echo "$(IFS=':' ; echo "${data_drives_warm[*]}")")"

    while ! gum confirm --affirmative="Confirm" --negative="Change" "Use these drives for warm data?"; do
        data_drives_warm=""
        readarray -t data_drives_warm <<<"$(pick_unassigned_device "warm data drives" --no-limit)"
        gum join "$(gum style --foreground=72 "Warm data drives:")" \
            "$(echo "$(IFS=':' ; echo "${data_drives_warm[*]}")")"
    done

    data_drives_hot=""
    if [ -n "$(unassigned_devices)" ]; then
        readarray -t data_drives_hot <<<"$(pick_unassigned_device "hot data drives" --no-limit)"
        gum join "$(gum style --foreground=72 "Hot data drives:")" \
            "$(echo "$(IFS=':' ; echo "${data_drives_hot[*]}")")"

        while ! gum confirm --affirmative="Confirm" --negative="Change" "Use these drives for hot data?"; do
            data_drives_hot=""
            readarray -t data_drives_hot <<<"$(pick_unassigned_device "hot data drives" --no-limit)"
            gum join "$(gum style --foreground=72 "Hot data drives:")" \
                "$(echo "$(IFS=':' ; echo "${data_drives_hot[*]}")")"
        done
    fi
}

function interactive_set_encryption() {
    data_password=""

    if ! gum confirm "Encrypt data drives?"; then
        return 0
    fi

    data_password="$(gum input --header=" Data filesystem encryption key" --placeholder="password" --cursor.mode="hide" --password)"

    while [[ ! "$data_password" = "$(gum input --header=" Confirm password" --placeholder="password" --cursor.mode="hide" --password)" ]]; do
        data_password="$(gum input --header=" Data filesystem encryption key (mismatch, try again)" --placeholder="password" --cursor.mode="hide" --password)"
    done

    tang_server="$(gum input --header=" Tang server (network signing)" --placeholder="address:port (leave blank to skip)")"

    if [ -n "$tang_server" ] && ! curl -fs "http://$tang_server/adv" >/dev/null; then
        gum log --level=error "Could not connect to Tang server: http://$tang_server"
        tang_server="$(gum input --header=" Tang server (network signing)" --placeholder="address:port")"
        if [ -n "$tang_server" ] && ! curl -fs "http://$tang_server/adv" >/dev/null; then
            gum log --level=error "Could not connect to Tang server: http://$tang_server"
            if ! gum confirm --affirmative="Use unreachable Tang server" --negative="Skip Tang" --selected.background=209 --prompt.foreground=181 "Proceed anyway?"; then
                tang_server=""
            fi
        fi
    fi

    if [ -n "$tang_server" ]; then
        gum join "$(gum style --foreground=72 "Tang server:")" "$tang_server"
        clevis_conf="{\"t\": 2, \"pins\": {\"tpm2\": {}, \"tang\": {\"url\": \"http://$tang_server\"}}}"
    else
        clevis_conf="{\"t\": 1, \"pins\": {\"tpm2\": {}}}"
    fi

    clevis_jwe="$(echo "$data_password" | clevis encrypt sss "$clevis_conf")"

    gum style --bold --foreground="72" "== Clevis JWE token =="
    echo "$clevis_jwe"
    gum style --bold --foreground="72" "== Clevis JWE token =="

    gum style --border=rounded --border-foreground="45" \
        "Paste the Clevis JWE content into secrets/clevis-$sysname.jwe and then push it"
    gum confirm --affirmative="Done" --negative="Abort" "Is the Clevis JWE file committed and pushed?"
    gum spin --title="Pulling..." --show-stdout -- git -C "$scriptdir" pull --rebase
    while [ ! -f "$scriptdir/secrets/clevis-$sysname.jwe" ]; do
        gum confirm --affirmative="Retry" --negative="Abort" --selected.background=209 --prompt.foreground=181 "File does not exist!" || exit 1
        gum spin --title="Pulling..." --show-stdout -- git -C "$scriptdir" pull --rebase
    done
    while [ "$(cat "$scriptdir/secrets/clevis-$sysname.jwe")" != "$clevis_jwe" ]; do
        gum confirm --affirmative="Retry" --negative="Abort" --selected.background=209 --prompt.foreground=181 "File content does not match!" || exit 1
        gum spin --title="Pulling..." --show-stdout -- git -C "$scriptdir" pull --rebase
    done
}

function interactive_format_data_bcachefs() {
    if lsblk -n -o LABEL | grep -q Data && \
        ! gum confirm --affirmative="Overwrite" --negative="Keep" --default=false "Data filesystem already exists, overwrite?"; then
        gum style "Reusing existing Data filesystem"
        return 0
    fi
    interactive_set_data_drives
    interactive_set_encryption
    format_bcachefs_drive_args
    gum join --align=center --vertical \
        "$(gum style --foreground=37 "bcachefs format command")" \
        "$(echo "bcachefs format ${bcachefs_data_opts[@]} ${bcachefs_drive_args[@]}" |
           gum style --border=rounded --border-foreground=37 --width="$(($COLUMNS - 4))")"
    if [ -z "$data_password" ]; then
        gum spin --title="Formatting data drives" -- bcachefs format "${bcachefs_data_opts[@]}" "${bcachefs_drive_args[@]}"
    else
        echo "$data_password" |
            gum spin --title="Formatting data drives" -- bcachefs format "${bcachefs_data_opts[@]}" "${bcachefs_drive_args[@]}"
    fi
}

# 
# Entrypoint

sysname="$(gum choose --header=" System designation" 'golgi (hetzner VM)' 'nucleus (bare-metal NAS)' | cut -d' ' -f1)"
gum join "$(gum style --foreground=72 "System:")" "$sysname"

if [ "$sysname" = "golgi" ]; then
    interactive_format_boot_btrfs
    generate_ssh_key
elif [ "$sysname" = "nucleus" ]; then
    interactive_format_boot_bcachefs
    generate_ssh_key
    interactive_format_data_bcachefs
fi

gum style --border=thick "Installing NixOS"

gum style "Disabling non-essential modules in flake.nix for a minimal install"
nix_disable_nonessential_modules

if ! gum confirm --affirmative="Continue" --negative="Abort" "Proceed with NixOS install?"; then
    gum join --align=center --vertical \
        "$(gum style --foreground=217 "Remaining install steps")" \
        "$(gum style --border=rounded --border-foreground=217 \
"1. cd ${scriptdir#"$(realpath "$(pwd)/")"}
2. nixos-install --root ${MNT} --flake .#${sysname}
3. umount -R ${MNT}
4. shutdown -h now")"
    exit 1
fi

nix-shell -p nixVersions.latest -p git --run "nixos-install --root ${MNT} --flake .#${sysname}"
umount -R "${MNT}"

gum confirm --affirmative="Shutdown" --negative="No" "Installation complete, shutdown now?" &&
    shutdown -h now

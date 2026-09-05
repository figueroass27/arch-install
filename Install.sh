#!/usr/bin/env bash

# ======================================================
# Shadowseeker27's Arch Install Script ─ Phase 1
# ======================================================

# Makes it so script exits on errors properly
set -euo pipefail

# ── Variables ─────────────────────────────────────────

# Edit before running
DISK="/dev/nvme0n1"
HOSTNAME="ephemeris"
USERNAME="carbon"
TIMEZONE="America/Chicago"
LOCALE="en_US.UTF-8"
KEYMAP="us"
if [[ "$DISK" == *"nvme"* ]]; then
    EFI_PART="${DISK}p1"
    ROOT_PART="${DISK}p2"
else
    EFI_PART="${DISK}1"
    ROOT_PART="${DISK}2"
fi
LUKS_LABEL="luks"
BTRFS_MOUNT_OPTS="noatime,compress=zstd,space_cache=v2"
SUBVOLS=("@" "@home" "@snapshots" "@var_log" "@var_cache_pacman")

# Micro code auto detect for amd / intel
CPU_VENDOR=$(grep -m1 'vendor_id' /proc/cpuinfo | awk '{print $3}')
if [[ "$CPU_VENDOR" == "AuthenticAMD" ]]; then
    UCODE="amd-ucode"
elif [[ "$CPU_VENDOR" == "GenuineIntel" ]]; then
    UCODE="intel-ucode"
else
    err "Unknown CPU vendor: $CPU_VENDOR — set UCODE manually"
fi

# ── Helpers ───────────────────────────────────────────

info()	{ echo -e "\n\e[1;34m[INFO]\e[0m $*"; }
ok()	{ echo -e "\e[1;32m[OK]\e[0m $*"; }
err()	{ echo -e "\e[1;31m[ERROR]\e[0m $*" >&2; exit 1; }

confirm() {
	read -rp "$1 [y/N]: " reply
	[[ "${reply,,}" == "y" ]] || err "Aborted."
}

# ── Preflight ────────────────────────────────────────

preflight() {
	info "Preflight checks"
	[[ -d /sys/firmware/efi ]] || err "Not booted in UEFI mode"
	ping -c1 archlinux.org &>/dev/null || err "No internet connection"
	[[ -b "$DISK" ]] || err "Disk $DISK not found."
	confirm "This will WIPE $DISK. Continue?"
	ok "Preflight passed"
}

# ── Disk Setup ────────────────────────────────────────

partition_disk() {
	info "Partitioning $DISK"
	sgdisk -n 1:0:+512M	-t 1:ef00 -c 1:"EFI" "$DISK"
	sgdisk -n s:0:0		-t 2:8300 -c 2:"ROOT" "$DISK"
	partprobe "$DISK"
	ok "Partitioned"
}

setup_luks() {
	info "Setting up LUKS encryption on $ROOT_PART"
	cryptsetup luksFormat --type luks2 "$ROOT_PART"
	cryptsetup open "$ROOT_PART" "$LUKS_LABEL"
	ok "LUKS opened as /dev/mapper/$LUKS_LABEL"
}

setup_btrfs() {
	info "Formatting with Btrfs and creating subvolumes"
	mkfs.btrfs -L root /dev/mapper/"$LUKS_LABEL"
	mount /dev/mapper/"$LUKS_LABEL" /mnt

	for sv in "${SUBVOLS[@]}"; do
		btrfs subvolume create /mnt/"$sv"
		ok "Created subvolume $sv"
	done

	umount /mnt
}

mount_subvols() {
	info "Mounting subvolumes"
	mount -o "${BTRFS_MOUNT_OPTS},subvol=@"					/dev/mapper/"$LUKS_LABEL" /mnt
	mkdir -p /mnt/{home,.snapshots,var/log,var/cache/pacman,boot}

	mount -o "${BTRFS_MOUNT_OPTS},subvol=@home"				/dev/mapper/"$LUKS_LABEL" /mnt/home
	mount -o "${BTRFS_MOUNT_OPTS},subvol=@snapshots"		/dev/mapper/"$LUKS_LABEL" /mnt/.snapshots
	mount -o "${BTRFS_MOUNT_OPTS},subvol=@var_log"			/dev/mapper/"$LUKS_LABEL" /mnt/var/log
	mount -o "${BTRFS_MOUNT_OPTS},subvol=@var_cache_pacman"	/dev/mapper/"$LUKS_LABEL" /mnt/var/cache/pacman

	# EFI
	mkfs.fat -F32 "$EFI_PART"
	mount "$EFI_PART" /mnt/boot
	ok "All subvolumes mounted"
}

# ── Base Install ──────────────────────────────────────

generate_fstab() {
	info "Generating fstab"
	genfstab -U /mnt >> /mnt/etc/fstab
	ok "fstab written - review at /mnt/etc/fstab"
}

install_base() {
	info "Running pacstrap"
	pacstrap -K /mnt \
		base base-devel linux linux-headers linux-firmware \
		btrfs-progs snapper snap-pac "${UCODE}" \
		networkmanager neovim git curl sudo
	ok "Base system installed"
}

# ── Chroot Handoff ────────────────────────────────────

run_chroot() {
	info "Copying chroot script and entering chroot"

	# Pass config variables into the chroot environment
	cat > /mnt/root/chroot_vars.sh <<EOF
HOSTNAME="$HOSTNAME"
USERNAME="$USERNAME"
TIMEZONE="$TIMEZONE"
LOCALE="$LOCALE"
KEYMAP="$KEYMAP"
LUKS_LABEL="$LUKS_LABEL"
ROOT_PART="$ROOT_PART"
UCODE="$UCODE"
EOF

	# curl -sL [insert link to script pt 2] -o /mnt/root/chroot.sh
	
	arch-chroot /mnt bash /root/Install-Chroot.sh
}

# ── CLEANUP ───────────────────────────────────────────

cleanup() {
	info "Unmounting and finishing"
	rm -f /mnt/root/chroot.sh /mnt/root/chroot_vars.sh
	umount -R /mnt
	cryptsetup close "$LUKS_LABEL"
	ok "Done. You can now reboot"
}

# ── Main ──────────────────────────────────────────────

main() {
	preflight
	partition_disk
	setup_luks
	setup_btrfs
	mount_subvols
	install_base
	generate_fstab
	run_chroot
	cleanup
}

main "$@"

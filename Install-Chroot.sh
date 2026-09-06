#!/usr/bin/env bash

# ======================================================
# Shadowseeker27's Arch Install Script ─ Phase 2
# ======================================================

# Makes it so script exits on errors properly
set -euo pipefail

# ── Load Vars From Phase 1 ────────────────────────────
source /root/chroot_vars.sh

# ── Helpers ───────────────────────────────────────────

info()	{ echo -e "\n\e[1;34m[INFO]\e[0m $*"; }
ok()	{ echo -e "\e[1;32m[OK]\e[0m $*"; }
err()	{ echo -e "\e[1;31m[ERROR]\e[0m $*" >&2; exit 1; }

# ── System Locale & Time ──────────────────────────────

setup_locale() {
	info "Setting locale"
    sed -i "s/^#${LOCALE}/${LOCALE}/" /etc/locale.gen
	locale-gen
	# setups up systemd backup locales
	echo "LANG=${LOCALE}" > /etc/locale.conf
	echo "KEYMAP=${KEYMAP}" > /etc/vconsole.conf
	systemctl enable ntpd
	ok "Locale set to $LOCALE"
}

setup_ntp() {
	info "Setting timezone"
	ln -sf /usr/share/zoneinfo/"$TIMEZONE" /etc/localetime
	hwclock --systohc
	ok "Timezone set to $TIMEZONE"
}

setup_hostname() {
	info "Setting hostname"
	echo "$HOSTNAME" > /etc/hostname
	cat > /etc/hosts <<EOF
127.0.0.1	localhost
::1			localhost
127.0.1.1	${HOSTNAME}.localdomain ${HOSTNAME}
EOF
	ok "Hostname set to $HOSTNAME"
}

# ── MKINITCPIO ────────────────────────────────────────

setup_initcpio() {
	info "Configuring mkinitcpio hooks"
	sed -i 's/^MODULES=.*/MODULES=(btrfs)/' /etc/mkinitcpio.conf

	sed -i 's/^HOOKS=.*/HOOKS=(base udev autodetect microcode modconf kms keyboard keymap consolefont block sd-encrypt filesystems fsck)/' \
		/etc/mkinitcpio.conf

	mkinitcpio -P
	ok "initramfs built"
}

# ── Systemd-Boot ──────────────────────────────────────

setup_bootloader() {
	info "Installing systemd-boot"
	bootctl install

	mkdir -p /boot/loader/entries

	# Main loader config
	cat > /boot/loader/loader.conf <<EOF
default arch.conf
timeout 3
console-mode max
editor no
EOF

luks_uuid=$(blkid -s UUID -o value ${ROOT_PART})

cat > /boot/loader/entries/arch.conf <<EOF
title Arch Linux
linux /vmlinuz-linux
initrd /${UCODE}.img
initrd /initramfs-linux.img
options rd.luks.name=${luks_uuid}=${LUKS_LABEL} root=/dev/mapper/${LUKS_LABEL} rootflags=subvol=@ rw quiet loglevel=3
EOF

ok "systemd-boot installed and configured"
}

# ── Snapper ──────────────────────────────────────

setup_snapper() {
	info "Setting-Up Snapper"
	# snapper wants to create /.snapshots itself - but we already have the
	# @snapshots subvolume mounted there, so we unmount, let snapper create
	# the config, then remount our subvolume over it
	mountpoint -q /.snapshots && umount /.snapshots
	rm -rf /.snapshots

	# snapper -c root create-config / 2>/dev/null || true
	snapper --no-dbus -c root create-config /

	# Replace the directroy snapper just created with our subvolume
	rm -rf /.snapshots
	mkdir /.snapshots
	mount -o noatime,compress=zstd,subvol=@snapshots /dev/mapper/"$LUKS_LABEL" /.snapshots
	chmod 750 /.snapshots

	# Snapshot retention policy - tune to taste
	sed -i \
		-e 's/^TIMELINE_MIN_AGE=.*/TIMELINE_MIN_AGE="1800"/' \
		-e 's/^TIMELINE_LIMIT_HOURLY=.*/TIMELINE_LIMIT_HOURLY="5"/' \
		-e 's/^TIMELINE_LIMIT_DAILY=.*/TIMELINE_LIMIT_DAILY="7"/' \
		-e 's/^TIMELINE_LIMIT_WEEKLY=.*/TIMELINE_LIMIT_WEEKLY="1"/' \
		-e 's/^TIMELINE_LIMIT_MONTHLY=.*/TIMELINE_LIMIT_MONTHLY="1"/' \
		-e 's/^TIMELINE_LIMIT_YEARLY=.*/TIMELINE_LIMIT_YEARLY="0"/' \
		/etc/snapper/configs/root
	
	cat /etc/snapper/configs/root

	ok "Created retention policy"

	# snap-pac hooks (auto snapshots on pacman install/remove/upgrade)
	# snap-pac was installed in pacstrap - just enable the snapper timers
	systemctl enable snapper-timeline.timer
	systemctl enable snapper-cleanup.timer

	ok "Snapper configured"
}

# ── Networking ──────────────────────────────────────

setup_networking() {
	info "Enabling NetworkManager"
	systemctl enable NetworkManager
	ok "NetworkManager enabled"
}

# ── User Setup ──────────────────────────────────────

setup_users() {
	info "Setting root password"
	passwd root

	info "Creating user: $USERNAME"
	useradd -m -G wheel,audio,video,storage,optical -s /bin/bash "$USERNAME"

	info "Setting password for $USERNAME"
	passwd "$USERNAME"

	# Allow wheel group to use sudo
	sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers
	ok "User $USERNAME created with sudo access"
}

# ── Additional Services ──────────────────────────────────────

setup_services() {
	info "Enabling base services"
	# systemctl enable bluetooth
	# systemctl enable cups
	ok "Services enabled"
}

# ── Stage Post-Install Script ──────────────────────────────────────

stage_postinstall() {
	info "Staging post-install script for $USERNAME"
	local home_dir="/home/$USERNAME"

	curl -sL https://raw.githubusercontent.com/you/arch-install/main/post-install.sh \
		-o "${home_dir}/post-install.sh"

	chown "$USERNAME:$USERNAME" "${home_dir}/post-install.sh"
	chmod +x "${home_dir}/post-install.sh"

	ok "post-install.sh is ready at ~/post-install.sh - run it after first boot"
}

# ── Main ──────────────────────────────────────

main() {
	setup_locale
	setup_ntp
	setup_hostname
	setup_initcpio
	setup_bootloader
	setup_snapper
	setup_networking
	setup_users
	setup_services
	stage_postinstall
}

main "$@"

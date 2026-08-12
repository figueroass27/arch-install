#!/usr/bin/env bash

# ======================================================
# Shadowseeker27's Arch Install Script ─ Phase 3 (run as user after first boot)
# ======================================================
set -euo pipefail

# ── Configuration ────────────────────────────

DOTFILES_REPO="https://github.com/figueroass27/dotfiles"
AUR_HELPER="yay"
DOTFILES_DIR="$HOME/Dotfiles"
PKGS_DIR="$HOME/Dotfiles/packages/"

# ── Helpers ────────────────────────────

info()	{ echo -e "\n\e[1;34m[INFO]\e[0m $*"; }
ok()	{ echo -e "\e[1;32m[OK]\e[0m $*"; }
err()	{ echo -e "\e[1;31m[ERROR]\e[0m $*" >&2; exit 1; }

# ── Preflight ────────────────────────────

preflight() {
	info "Preflight checks"
	[[ $EUID -ne 0 ]] || err "Run this as your user, not root."
	ping -c1 archlinux.org &>/dev/null || err "No internet connection."
	ok "Preflight passed"
}

# ── Pull Install Repo ────────────────────────────

pull_repo() {
	info "Cloning install repo"
	git clone "$DOTFILES_REPO" "$DOTFILES_DIR"
	ok "Repo cloned to $DOTFILES_DIR"
}

# ── AUR HELPER ────────────────────────────

install_aur_helper() {
	info "Installing $AUR_HELPER"

	if command -v "$AUR_HELPER" &>/dev/null; then
		ok "$AUR_HELPER already installed, skipping"
		return
	fi

	local tmp
	tmp=$(mktemp -d)
	git clone "https://aur.archlinux.org/${AUR_HELPER}.git" "$tmp/$AUR_HELPER"
	(cd "$tmp/$AUR_HELPER" && makepkg -si --noconfirm)
	rm -rf "$tmp"
	ok "$AUR_HELPER installed"
}

# ── Packages ────────────────────────────

install_packages() {
	info "Intalling pacman packages"
	if [[ -f "$PKGS_DIR/packages.txt" ]]; then
		grep -v '^\s*#' "$PKGS_DIR/packages.txt" | grep -v '^\s*$' | \
			$AUR_HELPER -S --needed --noconfirm -
		ok "Packages installed"
	fi
}

# ── Install Dotfiles ────────────────────────────

install_dotfiles() {
	info "Installing dotfiles via stow"

	# install stow if not present
	if ! command -v stow &>/dev/null; then
		yay -S --needed --noconfirm stow
	fi

	cd "$DOTFILES_DIR"

	# stow everything - the */ glob expands all subdirectories
	stow --restow --target="$HOME" */

	ok "Dotfiles symlinked"
}


# ── Snapper User Access ────────────────────────────

setup_snapper_access() {
	info "Granting snapper acces to $USER"
	sudo snapper -c root set-config ALLOW_USERS="$USER"
	sudo snapper -c home set-config ALLOW_USERS="$USER"
	ok "Snapper access granted"
}

# ── Cleanup ────────────────────────────

cleanup() {
	info "Cleaning up"
	ok "Done — system is fully configured."
	echo -e "\n\e[1;33mConsider rebooting to ensure all services start cleanly.\e[0m"
}

# ── Main ────────────────────────────

main() {
	preflight 
	pull_repo 
	install_aur_helper 
	install_packages
	install_dotfiles
	setup_snapper_access 
	cleanup
}

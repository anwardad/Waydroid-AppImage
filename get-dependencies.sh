#!/bin/sh
set -eu

ARCH=$(uname -m)

echo "Installing package dependencies..."
echo "---------------------------------------------------------------"
pacman -Syu --noconfirm waydroid python-pyclip curl jq unzip

echo "Installing debloated packages..."
echo "---------------------------------------------------------------"
get-debloated-pkgs --add-common --prefer-nano

make-aur-package zenity-rs-bin
make-aur-package 12to11-git

# No further changes needed

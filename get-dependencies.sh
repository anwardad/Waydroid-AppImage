#!/bin/sh

set -eu

ARCH=$(uname -m)

echo "Installing package dependencies..."
echo "---------------------------------------------------------------"
pacman -Syu --noconfirm waydroid python-pyclip curl unzip jq

# Install the appropriate image package
if [ "${DEVEL_RELEASE:-0}" = "1" ]; then
    echo "Installing GApps images (nightly build)..."
    pacman -S --noconfirm waydroid-image-gapps || pacman -S --noconfirm waydroid-image
else
    echo "Installing vanilla images (stable build)..."
    pacman -S --noconfirm waydroid-image
fi

echo "Installing debloated packages..."
echo "---------------------------------------------------------------"
get-debloated-pkgs --add-common --prefer-nano

make-aur-package zenity-rs-bin
make-aur-package 12to11-git

# If the application needs to be manually built that has to be done down here

# if you also have to make nightly releases check for DEVEL_RELEASE = 1
#
# if [ "${DEVEL_RELEASE-}" = 1 ]; then
# 	nightly build steps
# else
# 	regular build steps
# fi

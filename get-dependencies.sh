#!/bin/sh

set -eu

ARCH=$(uname -m)

echo "Installing package dependencies..."
echo "---------------------------------------------------------------"
pacman -Syu --noconfirm waydroid python-pyclip curl unzip jq

# The image script is included in the waydroid package
# No need to install separate image packages

echo "Installing debloated packages..."
echo "---------------------------------------------------------------"
get-debloated-pkgs --add-common --prefer-nano

make-aur-package zenity-rs-bin
make-aur-package 12to11-git

# If the application needs to be manually built that has to be done down here
# if [ "${DEVEL_RELEASE-}" = 1 ]; then
# 	nightly build steps
# else
# 	regular build steps
# fi

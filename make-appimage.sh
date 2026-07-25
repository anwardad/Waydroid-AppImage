#!/bin/sh
set -eu

ARCH=$(uname -m)
VERSION=$(pacman -Q waydroid | awk '{print $2; exit}')
export ARCH VERSION
export OUTPATH=./dist
export ADD_HOOKS="self-updater.bg.hook"
export UPINFO="gh-releases-zsync|${GITHUB_REPOSITORY%/*}|${GITHUB_REPOSITORY#*/}|latest|*$ARCH.AppImage.zsync"
export ICON=/usr/share/icons/hicolor/512x512/apps/waydroid.png
export DESKTOP=/usr/share/applications/Waydroid.desktop
export DEPLOY_PYTHON=1

# --------------------------------------------------------------------
# NEW: Inject Android images into the AppDir
# --------------------------------------------------------------------
IMAGE_DIR="./AppDir/usr/share/waydroid-extra/images"
mkdir -p "$IMAGE_DIR"

# Choose the appropriate URLs for your architecture ($ARCH)
# For x86_64 (most common), use these:
SYSTEM_URL="https://sourceforge.net/projects/waydroid/files/images/system/lineage/waydroid_x86_64/lineage-18.1-20250414-VANILLA-waydroid_x86_64-system.zip/download"
VENDOR_URL="https://sourceforge.net/projects/waydroid/files/images/vendor/waydroid_x86_64/lineage-18.1-20250414-MAINLINE-waydroid_x86_64-vendor.zip/download"

# For aarch64, adjust URLs accordingly (e.g., waydroid_arm64)
if [ "$ARCH" = "aarch64" ]; then
    SYSTEM_URL="https://sourceforge.net/projects/waydroid/files/images/system/lineage/waydroid_arm64/lineage-18.1-20250414-VANILLA-waydroid_arm64-system.zip/download"
    VENDOR_URL="https://sourceforge.net/projects/waydroid/files/images/vendor/waydroid_arm64/lineage-18.1-20250414-MAINLINE-waydroid_arm64-vendor.zip/download"
fi

# Download and extract
wget -O system.zip "$SYSTEM_URL"
wget -O vendor.zip "$VENDOR_URL"
unzip -q system.zip -d "$IMAGE_DIR"
unzip -q vendor.zip -d "$IMAGE_DIR"
rm -f system.zip vendor.zip

# Ensure the images are in the expected locations:
# $IMAGE_DIR/system.img and $IMAGE_DIR/vendor.img
# (Some archives may have subfolders; adjust extraction if needed)

# --------------------------------------------------------------------
# Deploy dependencies (unchanged)
# --------------------------------------------------------------------
mkdir -p ./AppDir/bin
cp -r /usr/lib/waydroid/* ./AppDir/bin
ln -s waydroid.py ./AppDir/bin/waydroid
quick-sharun \
    ./AppDir/bin/*            \
    /usr/bin/nft              \
    /usr/lib/libnftables.so*  \
    /usr/bin/dnsmasq          \
    /usr/bin/pgrep            \
    /usr/bin/12to11           \
    /usr/bin/init.lxc         \
    /usr/bin/lxc-*            \
    /usr/lib/lxc              \
    /etc/lxc                  \
    /usr/lib/libgtk-3.so*     \
    /usr/lib/libgbinder.so*   \
    /usr/lib/libglibutil.so*  \
    /usr/share/dbus-1         \
    /usr/share/polkit-1       \
    /usr/bin/zenity
find ./AppDir/share/dbus-1 ./AppDir/share/polkit-1 -type f ! -name '*waydro*' -delete

# Turn AppDir into AppImage
echo 'unset APPIMAGE_EXTRACT_AND_RUN' >> ./AppDir/.env
ADD_PERMA_ENV_VARS='APPIMAGE_EXTRACT_AND_RUN=1' quick-sharun --make-appimage

# Test (unchanged)
quick-sharun --simple-test ./dist/*.AppImage

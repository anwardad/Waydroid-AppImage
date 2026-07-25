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

# -------------------------------------------------------------------
# Download Android images using the official Waydroid script
# -------------------------------------------------------------------
IMAGE_DIR="./AppDir/usr/share/waydroid-extra/images"
mkdir -p "$IMAGE_DIR"

# Determine variant based on DEVEL_RELEASE
if [ "${DEVEL_RELEASE:-0}" = "1" ]; then
    SYSTEM_VARIANT="gapps"   # Nightly → GApps
else
    SYSTEM_VARIANT="vanilla" # Stable → Vanilla
fi
# Vendor always mainline
VENDOR_VARIANT="mainline"

# Map architecture names for the script (x86_64 → x86_64, aarch64 → arm64? Check)
# The script expects architecture names like "x86_64" or "arm64"
# According to Waydroid, for ARM64 they use "arm64", but the script might accept "aarch64"
# We'll pass the exact ARCH we have (x86_64 or aarch64) – it should work
echo "Downloading Android images (${SYSTEM_VARIANT}) for ${ARCH}..."
if /usr/lib/waydroid/tools/helpers/images.sh download \
    -o "$IMAGE_DIR" \
    -s "$SYSTEM_VARIANT" \
    -v "$VENDOR_VARIANT" \
    -a "$ARCH"; then
    echo "Images downloaded successfully."
else
    echo "ERROR: Failed to download images using official script." >&2
    exit 1
fi

# Verify that the images are present
if [ ! -f "$IMAGE_DIR/system.img" ] || [ ! -f "$IMAGE_DIR/vendor.img" ]; then
    echo "ERROR: system.img or vendor.img not found in $IMAGE_DIR after download." >&2
    exit 1
fi

# -------------------------------------------------------------------
# Deploy dependencies (unchanged)
# -------------------------------------------------------------------
mkdir -p ./AppDir/bin
cp -r /usr/lib/waydroid/* ./AppDir/bin
rm -f ./AppDir/bin/waydroid

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

# -------------------------------------------------------------------
# Create wrapper for waydroid that forces -i to bundled images
# -------------------------------------------------------------------
cat > ./AppDir/bin/waydroid << 'EOF'
#!/bin/sh
APPDIR="${APPDIR:-$(dirname "$(realpath "$0")")/..}"
IMAGE_DIR="$APPDIR/usr/share/waydroid-extra/images"

if [ "$1" = "init" ]; then
    shift
    exec python3 "$APPDIR/bin/waydroid.py" init -i "$IMAGE_DIR" "$@"
else
    exec python3 "$APPDIR/bin/waydroid.py" "$@"
fi
EOF
chmod +x ./AppDir/bin/waydroid

# -------------------------------------------------------------------
# Turn AppDir into AppImage
# -------------------------------------------------------------------
echo 'unset APPIMAGE_EXTRACT_AND_RUN' >> ./AppDir/.env
ADD_PERMA_ENV_VARS='APPIMAGE_EXTRACT_AND_RUN=1' quick-sharun --make-appimage

# -------------------------------------------------------------------
# Test the AppImage (simple test)
# -------------------------------------------------------------------
quick-sharun --simple-test ./dist/*.AppImage

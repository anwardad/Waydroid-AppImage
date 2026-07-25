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
# Copy pre-installed images from the system into the AppDir
# -------------------------------------------------------------------
IMAGE_DIR="./AppDir/usr/share/waydroid-extra/images"
mkdir -p "$IMAGE_DIR"

# The images are installed by pacman in get-dependencies.sh
# They are typically located in /usr/share/waydroid-extra/images/
# but might also be in /var/lib/waydroid/images/ depending on the package.
if [ -d "/usr/share/waydroid-extra/images" ]; then
    cp -r /usr/share/waydroid-extra/images/*.img "$IMAGE_DIR/"
elif [ -d "/var/lib/waydroid/images" ]; then
    cp -r /var/lib/waydroid/images/*.img "$IMAGE_DIR/"
else
    echo "ERROR: Could not find installed Android images." >&2
    exit 1
fi

# Verify that the images are present
if [ ! -f "$IMAGE_DIR/system.img" ] || [ ! -f "$IMAGE_DIR/vendor.img" ]; then
    echo "ERROR: system.img or vendor.img not found in $IMAGE_DIR" >&2
    exit 1
fi

echo "Android images successfully bundled."

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

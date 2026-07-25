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
# Helper: fetch the latest image zip URL from SourceForge via HTML scraping
# Arguments:
#   $1 = base path (e.g., "images/system/lineage/waydroid_x86_64")
#   $2 = variant to match in the zip filename (e.g., "VANILLA" or "MAINLINE")
# Returns: full download URL of the zip file
# -------------------------------------------------------------------
fetch_latest_image() {
    local base_path="$1"
    local variant="${2:-VANILLA}"
    local project="waydroid"
    local list_url="https://sourceforge.net/projects/${project}/files/${base_path}/"

    # Get the directory listing HTML
    html=$(wget -qO- "$list_url" 2>/dev/null || echo "")

    # Extract all subdirectory links (they point to dated folders)
    # Pattern: href="/projects/waydroid/files/images/.../lineage-18.1-YYYYMMDD-.../"
    dirs=$(echo "$html" | grep -o 'href="/projects/waydroid/files/'"${base_path}"'/[^"]*/"' | sed 's/.*\/files\/'"${base_path}"'\///;s/\/"//')

    # Find the latest dated directory (sort by the YYYYMMDD part)
    # Assumes format: lineage-18.1-YYYYMMDD-...
    latest_dir=$(echo "$dirs" | grep -E 'lineage-18\.1-[0-9]{8}-' | sort -t- -k3 -n | tail -n1)

    # Fallback: if no pattern match, take the first directory
    if [ -z "$latest_dir" ]; then
        latest_dir=$(echo "$dirs" | head -n1)
    fi

    if [ -z "$latest_dir" ]; then
        echo "ERROR: No subdirectories found for $base_path" >&2
        return 1
    fi

    # Now fetch the file list inside that directory
    file_list_url="https://sourceforge.net/projects/${project}/files/${base_path}/${latest_dir}/"
    file_html=$(wget -qO- "$file_list_url" 2>/dev/null || echo "")

    # Look for a zip file matching the variant (case-insensitive)
    zip_url=$(echo "$file_html" | grep -o 'href="[^"]*\.zip"' | grep -i "$variant" | head -n1 | sed 's/^href="//;s/"$//')

    # Fallback: any zip file
    if [ -z "$zip_url" ]; then
        zip_url=$(echo "$file_html" | grep -o 'href="[^"]*\.zip"' | head -n1 | sed 's/^href="//;s/"$//')
    fi

    if [ -z "$zip_url" ]; then
        echo "ERROR: No zip file found in $file_list_url" >&2
        return 1
    fi

    # Convert relative URL to absolute if needed
    if echo "$zip_url" | grep -q '^/'; then
        zip_url="https://sourceforge.net$zip_url"
    fi

    echo "$zip_url"
}

# -------------------------------------------------------------------
# Determine base paths and variant based on architecture and DEVEL_RELEASE
# -------------------------------------------------------------------
if [ "${DEVEL_RELEASE:-0}" = "1" ]; then
    variant="GAPPS"          # Nightly → use GApps (or change to your liking)
else
    variant="VANILLA"
fi

case "$ARCH" in
    x86_64)
        base_system="images/system/lineage/waydroid_x86_64"
        base_vendor="images/vendor/waydroid_x86_64"
        ;;
    aarch64)
        base_system="images/system/lineage/waydroid_arm64"
        base_vendor="images/vendor/waydroid_arm64"
        ;;
    *)
        echo "Unsupported architecture: $ARCH" >&2
        exit 1
        ;;
esac

# -------------------------------------------------------------------
# Fetch and extract images
# -------------------------------------------------------------------
IMAGE_DIR="./AppDir/usr/share/waydroid-extra/images"
mkdir -p "$IMAGE_DIR"

echo "Fetching latest system image (${variant}) for $ARCH..."
SYSTEM_URL=$(fetch_latest_image "$base_system" "$variant")
if [ -z "$SYSTEM_URL" ]; then
    echo "ERROR: Failed to get system image URL" >&2
    exit 1
fi

echo "Fetching latest vendor image (MAINLINE) for $ARCH..."
VENDOR_URL=$(fetch_latest_image "$base_vendor" "MAINLINE")
if [ -z "$VENDOR_URL" ]; then
    echo "ERROR: Failed to get vendor image URL" >&2
    exit 1
fi

# Download and extract
echo "Downloading system image from $SYSTEM_URL"
wget -O system.zip "$SYSTEM_URL"
echo "Downloading vendor image from $VENDOR_URL"
wget -O vendor.zip "$VENDOR_URL"

unzip -q system.zip -d "$IMAGE_DIR"
unzip -q vendor.zip -d "$IMAGE_DIR"
rm -f system.zip vendor.zip

# Ensure the .img files are directly in IMAGE_DIR (some archives have subfolders)
find "$IMAGE_DIR" -type f -name "*.img" -exec mv -n {} "$IMAGE_DIR"/ \; 2>/dev/null || true
find "$IMAGE_DIR" -type d -empty -delete 2>/dev/null || true

# -------------------------------------------------------------------
# Deploy dependencies
# -------------------------------------------------------------------
mkdir -p ./AppDir/bin
cp -r /usr/lib/waydroid/* ./AppDir/bin
rm -f ./AppDir/bin/waydroid   # we will replace with a wrapper

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

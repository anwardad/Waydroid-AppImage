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
# fetch_latest_image: scrape SourceForge directory listing (improved)
# Arguments: $1 = base_path (e.g., images/system/lineage/waydroid_x86_64)
#            $2 = variant (VANILLA, GAPPS, MAINLINE) – case-insensitive
# Returns: full download URL of the zip file, or empty on failure
# -------------------------------------------------------------------
fetch_latest_image() {
    local base_path="$1"
    local variant="${2:-VANILLA}"
    local project="waydroid"
    local list_url="https://sourceforge.net/projects/${project}/files/${base_path}/"

    # Fetch with browser-like headers and follow redirects
    html=$(wget -qO- -L \
        --header="Accept: text/html" \
        --user-agent="Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36" \
        "$list_url" 2>/dev/null || echo "")

    [ -z "$html" ] && return 1

    # Extract all subdirectory links (they point to dated folders)
    dirs=$(echo "$html" | grep -o 'href="/projects/waydroid/files/'"${base_path}"'/[^"]*/"' | \
           sed 's#.*/files/'"${base_path}"'/##;s#/"$##')

    # Find the latest dated directory (sort by the YYYYMMDD part)
    latest_dir=$(echo "$dirs" | grep -E 'lineage-[0-9]+\.[0-9]+-[0-9]{8}-' | sort -t- -k3 -n | tail -n1)
    [ -z "$latest_dir" ] && latest_dir=$(echo "$dirs" | head -n1)
    [ -z "$latest_dir" ] && return 1

    # Fetch file list inside that directory
    file_list_url="https://sourceforge.net/projects/${project}/files/${base_path}/${latest_dir}/"
    file_html=$(wget -qO- -L \
        --header="Accept: text/html" \
        --user-agent="Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36" \
        "$file_list_url" 2>/dev/null || echo "")
    [ -z "$file_html" ] && return 1

    # Look for a zip file matching the variant (case-insensitive)
    zip_url=$(echo "$file_html" | grep -o 'href="[^"]*\.zip"' | grep -i "$variant" | head -n1 | sed 's#^href="##;s#"$##')
    [ -z "$zip_url" ] && zip_url=$(echo "$file_html" | grep -o 'href="[^"]*\.zip"' | head -n1 | sed 's#^href="##;s#"$##')
    [ -z "$zip_url" ] && return 1

    # Convert relative URL to absolute
    echo "$zip_url" | grep -q '^/' && zip_url="https://sourceforge.net$zip_url"
    echo "$zip_url"
}

# -------------------------------------------------------------------
# Static fallback URLs (using your working system link)
# We also construct vendor and other variant URLs based on the same date.
# You can edit these if you have specific URLs.
# -------------------------------------------------------------------
# Base static URL – we extract the date and architecture from your link
# Your link: https://sourceforge.net/.../lineage-20.0-20260403-VANILLA-waydroid_x86_64-system.zip/download
# We'll use the same date and arch for vendor and GAPPS.

# For x86_64 vanilla system – your working URL
STATIC_SYSTEM_VANILLA_X86_64="https://sourceforge.net/projects/waydroid/files/images/system/lineage/waydroid_x86_64/lineage-20.0-20260403-VANILLA-waydroid_x86_64-system.zip/download"

# Construct GAPPS for x86_64 (assume same date)
STATIC_SYSTEM_GAPPS_X86_64="https://sourceforge.net/projects/waydroid/files/images/system/lineage/waydroid_x86_64/lineage-20.0-20260403-GAPPS-waydroid_x86_64-system.zip/download"

# Vendor for x86_64 (MAINLINE)
STATIC_VENDOR_X86_64="https://sourceforge.net/projects/waydroid/files/images/vendor/waydroid_x86_64/lineage-20.0-20260403-MAINLINE-waydroid_x86_64-vendor.zip/download"

# For aarch64 – you might need to adjust these if you have aarch64 images
# They may not exist; you can leave them as fallback or remove.
STATIC_SYSTEM_VANILLA_ARM64="https://sourceforge.net/projects/waydroid/files/images/system/lineage/waydroid_arm64/lineage-20.0-20260403-VANILLA-waydroid_arm64-system.zip/download"
STATIC_SYSTEM_GAPPS_ARM64="https://sourceforge.net/projects/waydroid/files/images/system/lineage/waydroid_arm64/lineage-20.0-20260403-GAPPS-waydroid_arm64-system.zip/download"
STATIC_VENDOR_ARM64="https://sourceforge.net/projects/waydroid/files/images/vendor/waydroid_arm64/lineage-20.0-20260403-MAINLINE-waydroid_arm64-vendor.zip/download"

# -------------------------------------------------------------------
# Determine which static URLs to use based on ARCH and DEVEL_RELEASE
# -------------------------------------------------------------------
if [ "${DEVEL_RELEASE:-0}" = "1" ]; then
    variant="GAPPS"
else
    variant="VANILLA"
fi

case "$ARCH" in
    x86_64)
        base_system="images/system/lineage/waydroid_x86_64"
        base_vendor="images/vendor/waydroid_x86_64"
        static_system=$( [ "$variant" = "GAPPS" ] && echo "$STATIC_SYSTEM_GAPPS_X86_64" || echo "$STATIC_SYSTEM_VANILLA_X86_64" )
        static_vendor="$STATIC_VENDOR_X86_64"
        ;;
    aarch64)
        base_system="images/system/lineage/waydroid_arm64"
        base_vendor="images/vendor/waydroid_arm64"
        static_system=$( [ "$variant" = "GAPPS" ] && echo "$STATIC_SYSTEM_GAPPS_ARM64" || echo "$STATIC_SYSTEM_VANILLA_ARM64" )
        static_vendor="$STATIC_VENDOR_ARM64"
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

# System image
echo "Fetching latest system image (${variant}) for $ARCH..."
SYSTEM_URL=$(fetch_latest_image "$base_system" "$variant" 2>/dev/null || echo "")
if [ -z "$SYSTEM_URL" ]; then
    echo "Scraping failed. Using static fallback: $static_system"
    SYSTEM_URL="$static_system"
fi

# Vendor image
echo "Fetching latest vendor image (MAINLINE) for $ARCH..."
VENDOR_URL=$(fetch_latest_image "$base_vendor" "MAINLINE" 2>/dev/null || echo "")
if [ -z "$VENDOR_URL" ]; then
    echo "Scraping failed. Using static fallback: $static_vendor"
    VENDOR_URL="$static_vendor"
fi

# Download and extract
echo "Downloading system image from $SYSTEM_URL"
wget -O system.zip "$SYSTEM_URL"
echo "Downloading vendor image from $VENDOR_URL"
wget -O vendor.zip "$VENDOR_URL"

unzip -q system.zip -d "$IMAGE_DIR"
unzip -q vendor.zip -d "$IMAGE_DIR"
rm -f system.zip vendor.zip

# Ensure .img files are directly in IMAGE_DIR
find "$IMAGE_DIR" -type f -name "*.img" -exec mv -n {} "$IMAGE_DIR"/ \; 2>/dev/null || true
find "$IMAGE_DIR" -type d -empty -delete 2>/dev/null || true

# Verify
if [ ! -f "$IMAGE_DIR/system.img" ] || [ ! -f "$IMAGE_DIR/vendor.img" ]; then
    echo "ERROR: system.img or vendor.img not found after extraction." >&2
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

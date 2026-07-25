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
# Helper function to fetch the latest image URL from SourceForge
# Arguments: $1 = base path (e.g., "system/lineage/waydroid_x86_64")
#            $2 = variant (VANILLA or GAPPS) - optional, default VANILLA
# Returns: URL to the .zip file
# -------------------------------------------------------------------
fetch_latest_image() {
    local base_path="$1"
    local variant="${2:-VANILLA}"
    local project="waydroid"
    local api_url="https://sourceforge.net/rest/p/${project}/files/${base_path}/"

    # Use jq to parse the JSON response; fallback to a crude grep if jq not found
    if command -v jq >/dev/null 2>&1; then
        # Get the list of subdirectories (each is a dated release)
        # Pick the one with the largest date (lexicographically)
        latest_dir=$(curl -s "$api_url" | jq -r '.subdirs[] | .name' | sort -r | head -n1)
        if [ -z "$latest_dir" ]; then
            echo "ERROR: No subdirectories found for $base_path" >&2
            return 1
        fi
        # Now get files in that subdir, look for a zip matching the variant
        file_url=$(curl -s "${api_url}${latest_dir}/" | jq -r --arg variant "$variant" '.files[] | select(.name | test(".*-'"$variant"'-.*\\.zip$")) | .download_url')
        if [ -z "$file_url" ]; then
            # If no variant-specific file, fallback to any zip (maybe there's only one)
            file_url=$(curl -s "${api_url}${latest_dir}/" | jq -r '.files[] | select(.name | endswith(".zip")) | .download_url' | head -n1)
        fi
        echo "$file_url"
    else
        # Fallback: use wget to get the directory listing HTML and parse
        # (This is less reliable but works as a fallback)
        echo "WARNING: jq not installed, using fallback HTML parsing" >&2
        local list_url="https://sourceforge.net/projects/${project}/files/${base_path}/"
        # Get the latest directory by sorting the table rows by date (crude)
        latest_dir=$(wget -qO- "$list_url" | grep -o 'href="[^"]*"' | grep -E '/files/'"${base_path}"'/[0-9]{8}-' | head -n1 | sed 's/.*\/files\///;s/".*//')
        if [ -z "$latest_dir" ]; then
            # fallback: pick the first directory listed
            latest_dir=$(wget -qO- "$list_url" | grep -o 'href="[^"]*"' | grep -E '/files/'"${base_path}"'/' | head -n1 | sed 's/.*\/files\///;s/".*//')
        fi
        if [ -z "$latest_dir" ]; then
            echo "ERROR: Could not determine latest directory" >&2
            return 1
        fi
        # Now fetch the zip file from that directory
        file_url=$(wget -qO- "${list_url}${latest_dir}/" | grep -o 'href="[^"]*"' | grep -E '\.zip' | head -n1 | sed 's/.*href="//;s/".*//' | sed 's|^/|https://sourceforge.net|')
        echo "$file_url"
    fi
}

# -------------------------------------------------------------------
# Determine base paths and variants based on architecture and DEVEL_RELEASE
# -------------------------------------------------------------------
if [ "${DEVEL_RELEASE:-0}" = "1" ]; then
    variant="GAPPS"   # Use GApps for nightly builds (or change to your preference)
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
# Vendor images usually don't have a variant, we just fetch the MAINLINE one
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

# Ensure the files are named correctly (some archives may have subdirs)
# Move any .img files to the root of IMAGE_DIR
find "$IMAGE_DIR" -type f -name "*.img" -exec mv -n {} "$IMAGE_DIR"/ \; 2>/dev/null || true
# Remove empty subdirectories
find "$IMAGE_DIR" -type d -empty -delete 2>/dev/null || true

# -------------------------------------------------------------------
# Deploy dependencies (unchanged)
# -------------------------------------------------------------------
mkdir -p ./AppDir/bin
cp -r /usr/lib/waydroid/* ./AppDir/bin
# We'll replace the symlink with a wrapper later, so remove it
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
# Create a wrapper script for waydroid that injects -i
# -------------------------------------------------------------------
cat > ./AppDir/bin/waydroid << 'EOF'
#!/bin/sh
# Wrapper for waydroid to force usage of bundled images
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
# Simple test (adjust timeout if needed)
# -------------------------------------------------------------------
quick-sharun --simple-test ./dist/*.AppImage

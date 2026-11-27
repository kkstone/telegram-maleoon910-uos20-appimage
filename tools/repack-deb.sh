#!/bin/sh
# Repack the hardware-accel deb with the AppImage freshly built by this repo.
#
# The base deb in assets/ is the stable carrier: it owns the ANGLE shim libs,
# ICD manifest, Vulkan loader, launcher, desktop entry and icon under
# /opt/telegram/lib, /usr/local/bin and /usr/share.  The only thing that must
# track each new Telegram release is the embedded AppImage at
# /opt/telegram/bin/telegram.  This script swaps exactly that file and rewrites
# the package/desktop version strings so a single `dpkg -i` is all a user needs.
set -eu

REPO_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$REPO_ROOT"

NVR=${1:-$(cat LATEST_VERSION)}           # e.g. 7.4.4-alt1 (ALT NVR)
BASE_DEB=${2:-assets/telegram-desktop-hwaccel_7.4.4-1_arm64.deb}
OUT_DEB=${3:-dist/telegram-desktop-hwaccel_$(printf '%s' "$NVR" | sed 's/-alt[0-9]*$//')-1_arm64.deb}

[ -n "$NVR" ] || { echo "ERROR: empty version" >&2; exit 1; }
[ -f "$BASE_DEB" ] || { echo "ERROR: base deb missing: $BASE_DEB (git lfs pull?)" >&2; exit 1; }
APPIMAGE=$(find dist -maxdepth 1 -name '*.AppImage' -type f | head -n 1)
[ -n "$APPIMAGE" ] || { echo "ERROR: no AppImage found in dist/" >&2; exit 1; }
command -v dpkg-deb >/dev/null || { echo "ERROR: dpkg-deb not found" >&2; exit 1; }

PKGVER=$(printf '%s' "$NVR" | sed 's/-alt[0-9]*$//')
DEBVER="${PKGVER}-1"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

echo "Repacking deb with fresh AppImage"
echo "  base deb : $BASE_DEB"
echo "  appimage : $APPIMAGE"
echo "  ALT NVR  : $NVR"
echo "  deb ver  : $DEBVER"
echo "  output   : $OUT_DEB"

# dpkg-deb -R extracts control files into DEBIAN/ and payload into the tree.
dpkg-deb -R "$BASE_DEB" "$WORK/root"

# Swap only the embedded AppImage. Everything else in the base deb stays
# byte-for-byte (ANGLE shim, ICD, Vulkan loader, launcher, icon, desktop file).
cp -f "$APPIMAGE" "$WORK/root/opt/telegram/bin/telegram"
chmod 755 "$WORK/root/opt/telegram/bin/telegram"

# Keep package metadata in sync with the freshly built version.
sed -i "s/^Version:.*/Version: ${DEBVER}/" "$WORK/root/DEBIAN/control"
sed -i "s/^Description: Telegram .*/Description: Telegram ${NVR} with ANGLE\/Vulkan\/Maleoon hardware acceleration/" "$WORK/root/DEBIAN/control"
sed -i "s/^ Telegram Desktop [0-9][0-9.]* / Telegram Desktop ${NVR} /" "$WORK/root/DEBIAN/control"
DESKTOP="$WORK/root/usr/share/applications/org.telegram.desktop.desktop"
[ ! -f "$DESKTOP" ] || sed -i "s/^X-AppImage-Version=.*/X-AppImage-Version=${NVR}/" "$DESKTOP"

mkdir -p "$(dirname "$OUT_DEB")"
dpkg-deb --root-owner-group --build "$WORK/root" "$OUT_DEB"

echo "Verifying $OUT_DEB"
dpkg-deb -f "$OUT_DEB" Package Version Architecture
dpkg-deb -c "$OUT_DEB" | grep 'opt/telegram/bin/telegram'
echo "embedded AppImage md5: $(md5sum "$APPIMAGE" | cut -d' ' -f1)"
echo "deb md5:              $(md5sum "$OUT_DEB" | cut -d' ' -f1)"

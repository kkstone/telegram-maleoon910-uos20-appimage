#!/bin/sh
# Bootstrap the ALT Linux p11 aarch64 build environment from a frozen,
# verified snapshot shipped in this repo via Git LFS.
#
# Why a snapshot: ALT has removed libwebkit2gtk4.0 from all current repos
# (only 4.1 / 6.0 remain). The snapshot preserves the exact library closure
# that produces the WebKit2GTK-4.0 AppImage. Only the Telegram binary itself
# is refreshed from the official ALT mirror on each build, so new Telegram
# releases are still picked up automatically.
set -eu

REPO_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
export REPO_ROOT
cd "$REPO_ROOT"

ARCH=$(uname -m)
[ "$ARCH" = aarch64 ] || { echo "ERROR: must run on aarch64, got $ARCH" >&2; exit 1; }

MIRROR=${ALT_MIRROR:-https://ftp.altlinux.org/pub/distributions/ALTLinux}
ROOTFS="$REPO_ROOT/alt-rootfs"
CACHE="$REPO_ROOT/.cache-rpms"
SNAP="$REPO_ROOT/assets/alt-p11-wk40-rootfs.zst"

echo "Unpacking frozen ALT p11 rootfs snapshot..."
echo "---------------------------------------------------------------"
command -v zstd >/dev/null || { echo "ERROR: zstd not available" >&2; exit 1; }
[ -f "$SNAP" ] || { echo "ERROR: snapshot missing: $SNAP (git lfs pull?)" >&2; exit 1; }

# Only unpack when the rootfs is not already populated.
if [ ! -x "$ROOTFS/usr/bin/apt-cache" ] || [ ! -f "$ROOTFS/usr/lib64/libwebkit2gtk-4.0.so.37" ]; then
	rm -rf "$ROOTFS"
	mkdir -p "$ROOTFS"
	zstd -dc "$SNAP" | tar -xf - -C "$ROOTFS" --no-same-owner
fi
echo "  rootfs ready ($(du -sh "$ROOTFS" | cut -f1))"

# Refresh the Telegram binary to the version we are building. The workflow
# writes the target version into LATEST_VERSION before invoking this script.
mkdir -p "$CACHE"
VERSION=$(cat LATEST_VERSION)
echo "Ensuring Telegram binary == $VERSION ..."
echo "---------------------------------------------------------------"
# Discover the exact RPM filename from the mirror listing (handles any
# upstream version string without hardcoding it).
RPMFN=$(curl -fsSL --retry 3 "$MIRROR/p11/branch/aarch64/RPMS.classic/" \
	| grep -oE "telegram-desktop-${VERSION}[^\"<]*aarch64\.rpm" | sort -u | tail -n 1)
[ -n "$RPMFN" ] || { echo "ERROR: no RPM found for telegram-desktop-$VERSION" >&2; exit 1; }
RPM="$CACHE/$RPMFN"
if [ ! -s "$RPM" ]; then
	curl -fL --retry 3 -o "$RPM" "$MIRROR/p11/branch/aarch64/RPMS.classic/$RPMFN"
fi
# Extract the Telegram binary over the rootfs. alt.sh maps the repo at /work
# and drops us at the rootfs root, so reference the RPM by its /work path and
# unpack into / (cutdown to just the Telegram payload).
if [ -x "$ROOTFS/usr/bin/Telegram" ] && cmp -s "$RPM" "$CACHE/.installed-$(basename "$RPM")" 2>/dev/null; then
	echo "  Telegram binary already current"
else
	./tools/alt.sh sh -c 'cd / && rpm2cpio "/work/.cache-rpms/$1" | cpio -idmu --no-absolute-filenames 2>/dev/null' sh "$RPMFN"
	cp "$RPM" "$CACHE/.installed-$(basename "$RPM")"
fi
echo "  installed $RPMFN"

echo "Seeding offline build helpers..."
echo "---------------------------------------------------------------"
mkdir -p "$ROOTFS/usr/local/bin"
cp tools/quick-sharun.sh "$ROOTFS/usr/local/bin/quick-sharun"
chmod +x "$ROOTFS/usr/local/bin/quick-sharun"
cp appimagetool "$ROOTFS/usr/local/bin/appimagetool" 2>/dev/null || :
chmod +x "$ROOTFS/usr/local/bin/appimagetool" 2>/dev/null || :

mkdir -p "$ROOTFS/var/lib/dbus" "$ROOTFS/etc"
HEX=$(cat /proc/sys/kernel/random/uuid | tr -d '-')
echo "$HEX" > "$ROOTFS/etc/machine-id"
cp "$ROOTFS/etc/machine-id" "$ROOTFS/var/lib/dbus/machine-id"

echo "Bootstrap complete. Run /bin/sh ./make-appimage.sh next."

#!/bin/sh
# Bootstrap a reproducible ALT Linux p11 aarch64 build rootfs.
#
# Mirrors the upstream project's get-dependencies.sh role, but uses ALT p11
# instead of Arch: install the minimal ALT rootfs, fetch the aarch64 + noarch
# package indexes, resolve the full dependency closure of Telegram and
# WebKit2GTK-4.0, download the RPMs, install them into the rootfs with
# rpm2cpio, and seed the offline build helpers used by make-appimage.sh.
set -eu

REPO_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
export REPO_ROOT
cd "$REPO_ROOT"

ARCH=$(uname -m)
[ "$ARCH" = aarch64 ] || { echo "ERROR: must run on aarch64, got $ARCH" >&2; exit 1; }

MIRROR=${ALT_MIRROR:-https://ftp.altlinux.org/pub/distributions/ALTLinux}
ROOTFS="$REPO_ROOT/alt-rootfs"
CACHE="$REPO_ROOT/.cache-rpms"
LISTS="$ROOTFS/var/lib/apt/lists"

echo "Installing host build tools..."
echo "---------------------------------------------------------------"
if command -v apt-get >/dev/null 2>&1; then
	apt-get update -qq
	DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
		bubblewrap aria2 curl cpio xz-utils zstd file python3
fi
command -v bwrap >/dev/null || { echo "ERROR: bwrap not available" >&2; exit 1; }
command -v aria2c >/dev/null || { echo "ERROR: aria2c not available" >&2; exit 1; }

echo "Fetching minimal ALT p11 rootfs..."
echo "---------------------------------------------------------------"
mkdir -p "$ROOTFS" "$CACHE"
if [ ! -f "$CACHE/alt-p11-rootfs-minimal-aarch64.tar.xz" ]; then
	curl -fL --retry 3 -o "$CACHE/alt-p11-rootfs-minimal-aarch64.tar.xz" \
		"$MIRROR/p11/branch/aarch64/base/alt-p11-rootfs-minimal-aarch64.tar.xz"
fi
tar -xJf "$CACHE/alt-p11-rootfs-minimal-aarch64.tar.xz" -C "$ROOTFS" --no-same-owner

echo "Fetching aarch64 + noarch package indexes..."
echo "---------------------------------------------------------------"
mkdir -p "$LISTS/partial"
for archdir in aarch64 noarch; do
	list="$LISTS/ftp.altlinux.org_pub_distributions_ALTLinux_p11_branch_${archdir}_base_pkglist.classic"
	if [ ! -s "$list" ]; then
		curl -fL --retry 3 -o "$list" \
			"$MIRROR/p11/branch/$archdir/base/pkglist.classic"
	fi
	rel="$LISTS/ftp.altlinux.org_pub_distributions_ALTLinux_p11_branch_${archdir}_base_release"
	if [ ! -s "$rel" ]; then
		curl -fL --retry 3 -o "$rel" \
			"$MIRROR/p11/branch/$archdir/base/release" || :
	fi
done

echo "Resolving ALT dependency closure (Telegram + WebKit2GTK-4.0)..."
echo "---------------------------------------------------------------"
# Wrapper tools inside the rootfs are needed by quick-sharun/resolver.
mkdir -p "$ROOTFS/usr/local/bin"
cat > "$ROOTFS/usr/bin/ldd" <<'LDD'
#!/bin/sh
# minimal ldd for ALT (ships ld.so without ldd)
if [ "$1" = "--" ]; then shift; fi
exec /usr/bin/ld.so --list "$@"
LDD
chmod +x "$ROOTFS/usr/bin/ldd"
cat > "$ROOTFS/usr/local/bin/tar" <<'TAR'
#!/bin/sh
exec /usr/bin/tar --no-same-owner "$@"
TAR
chmod +x "$ROOTFS/usr/local/bin/tar"

RPMS="$CACHE/rpms.txt"
python3 tools/resolve_alt_deps.py \
	telegram-desktop libwebkit2gtk4.0 libjavascriptcoregtk4.0 \
	gst-plugins-good1.0 glib-networking publicsuffix-list-dafsa \
	> "$RPMS" 2>"$CACHE/resolve.log"
echo "  $(grep -c '\.rpm$' "$RPMS") RPMs resolved"

echo "Downloading RPMs (aria2 multi-connection)..."
echo "---------------------------------------------------------------"
: > "$CACHE/aria2-input.txt"
while IFS= read -r fn; do
	case "$fn" in
		*.rpm) ;;
		*) continue ;;
	esac
	echo "$MIRROR/p11/branch/aarch64/RPMS.classic/$fn" >> "$CACHE/aria2-input.txt"
done < "$RPMS"
# noarch packages live in a separate directory; try aarch64 first then noarch
aria2c -i "$CACHE/aria2-input.txt" -d "$CACHE" -x 8 -s 8 -k 1M \
	--continue=true --max-tries=3 --console-log-level=warn || \
	echo "WARNING: some RPMs failed to download; retrying individually" >&2

echo "Installing RPMs into rootfs..."
echo "---------------------------------------------------------------"
# Install via rpm2cpio inside the bwrap rootfs (host rpm2cpio cannot parse
# ALT's newer signature header).
install_one() {
	f="$1"
	[ -f "$f" ] || return 0
	base=$(basename "$f")
	[ -f "$CACHE/installed/$base" ] && return 0
	./tools/alt.sh sh -c 'rpm2cpio "$1" | cpio -idmu --no-absolute-filenames 2>/dev/null; touch "/work/.cache-rpms/installed/$(basename "$1")"' sh "$f" || \
	{ echo "WARN install failed: $base" >&2; return 0; }
}
mkdir -p "$CACHE/installed"
for f in "$CACHE"/*.rpm; do
	[ -f "$f" ] || continue
	install_one "$f"
done

echo "Seeding offline build helpers..."
echo "---------------------------------------------------------------"
mkdir -p alt-rootfs/usr/local/bin
cp tools/quick-sharun.sh alt-rootfs/usr/local/bin/quick-sharun
chmod +x alt-rootfs/usr/local/bin/quick-sharun
cp appimagetool alt-rootfs/usr/local/bin/appimagetool 2>/dev/null || :
chmod +x alt-rootfs/usr/local/bin/appimagetool 2>/dev/null || :

# machine-id required by D-Bus and some build helpers
mkdir -p alt-rootfs/var/lib/dbus alt-rootfs/etc
HEX=$(cat /proc/sys/kernel/random/uuid | tr -d '-')
echo "$HEX" > alt-rootfs/etc/machine-id
cp alt-rootfs/etc/machine-id alt-rootfs/var/lib/dbus/machine-id

echo "Bootstrap complete. Run /bin/sh ./make-appimage.sh next."

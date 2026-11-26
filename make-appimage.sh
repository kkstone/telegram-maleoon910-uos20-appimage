#!/bin/sh
# Build the aarch64 Telegram AppImage entirely from ALT Linux p11 libraries,
# with ONLY WebKit2GTK-4.0 (no 6.0 / 4.1 stacks), and swap the bundled libEGL
# for the ANGLE/Maleoon hardware-acceleration shim.
#
# The resulting AppImage must be paired with the hwaccel deb shipped in
# assets/ (or a GitHub Release asset): that deb installs the ANGLE libraries
# under /opt/telegram/lib which the shim dlopens at runtime.
set -eu

REPO_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
export REPO_ROOT
cd "$REPO_ROOT"

ARCH=$(uname -m)
VERSION=$(cat LATEST_VERSION)
export ARCH VERSION
export APPDIR=./AppDir
export OUTPATH=./dist
export ADD_HOOKS="self-updater.hook"
export UPINFO="gh-releases-zsync|${GITHUB_REPOSITORY:-kkstone/telegram-maleoon910-uos20-appimage}|latest|*$ARCH.AppImage.zsync"
export ICON=/work/icon256.png
export DESKTOP=/work/telegram.desktop
export DEPLOY_OPENGL=1
export DEPLOY_PIPEWIRE=1
export LIB_DIR=/usr/lib64
export WEBKIT2GTK_DIR=/usr/libexec/webkit2gtk-4.0
export DEPLOY_WEBKIT2GTK=1
export APPIMAGETOOL=/work/appimagetool
export I_WANT_FAT_APPIMAGE=1

rm -rf "$APPDIR"
mkdir -p "$APPDIR"
tar -xf /work/sharun+helper-libs-aarch64.tar -C "$APPDIR" sharun dash dash-COPYING 2>/dev/null || true
chmod +x "$APPDIR"/sharun "$APPDIR"/dash 2>/dev/null || true

# quick-sharun looks for its helper tarball in $TMPDIR. Seed it from the copy
# shipped in this repo so the build is fully offline (CI runners block some
# GitHub release downloads; the tarball checksum still gets verified).
_TMPDIR=${TMPDIR:-/tmp}
cp /work/sharun+helper-libs-aarch64.tar "$_TMPDIR/sharun+helper-libs-aarch64.tar" 2>/dev/null || :
# Also seed appimagetool and cross-libc-dlopen so the build needs no network.
[ -f /work/appimagetool ] && cp /work/appimagetool "$_TMPDIR/appimagetool" 2>/dev/null || :
chmod +x "$_TMPDIR/appimagetool" 2>/dev/null || :
[ -f /work/cross-libc-dlopen-aarch64.tar ] && \
	cp /work/cross-libc-dlopen-aarch64.tar "$_TMPDIR/cross-libc-dlopen-aarch64.tar" 2>/dev/null || :

# Deploy Telegram + only the WebKit2GTK-4.0 ABI. libsoup 2.4 and ICU are
# pulled in recursively by quick-sharun's ldd closure.
quick-sharun \
	/usr/bin/Telegram \
	/usr/lib64/libjpeg.so.62 \
	/usr/lib64/libcap.so.2 \
	/usr/lib64/libwebkit2gtk-4.0.so.37 \
	/usr/lib64/libjavascriptcoregtk-4.0.so.18 \
	/usr/lib64/libsoup-2.4.so.1 \
	/usr/lib64/webkit2gtk-4.0/injected-bundle/libwebkit2gtkinjectedbundle.so
echo 'DESKTOPINTEGRATION=0' >> "$APPDIR"/.env

# Map rewritten /usr/lib64 and /usr/libexec prefixes into the bundled lib dir
# so injected-bundle and helper paths resolve inside the AppImage sandbox.
for hook in "$APPDIR"/bin/*path-mapping*.hook; do
	[ -f "$hook" ] || continue
	cat >> "$hook" <<'HOOK'

# Map rewritten /usr/lib64 and /usr/libexec prefixes into the bundled lib.
# WebKitGTK hardcodes /usr/lib64/<abi>/injected-bundle/...; quick-sharun leaves
# the "64"/"exec" suffix behind on the random /tmp path.
if [ -n "$_tmp_lib" ]; then
	LC_ALL=C ln -sfn "$APPDIR"/lib /tmp/"$_tmp_lib"64 || :
	LC_ALL=C ln -sfn "$APPDIR"/lib /tmp/"$_tmp_lib"exec || :
fi
HOOK
done

# HiDPI cursor, audio backend, TLS/proxy, GStreamer + public-suffix hooks.
cp /work/cursor-dpi.hook "$APPDIR"/bin/07-cursor-dpi.hook
cp /work/audio-backend.hook "$APPDIR"/bin/08-audio-backend.hook
cp /work/tls-proxy.hook "$APPDIR"/bin/09-tls-proxy.hook
cp /work/media-psl.hook "$APPDIR"/bin/09-media-psl.hook
chmod +x "$APPDIR"/bin/0{7,8,9}-*.hook
mkdir -p "$APPDIR"/share/pipewire "$APPDIR"/bin
cp /work/pipewire-client.conf "$APPDIR"/share/pipewire/client.conf
cp /work/alsoft.conf "$APPDIR"/bin/alsoft.conf

# GnuTLS trust store: ALT hard-codes its CA bundle path; patch it to the
# /tmp symlink that 09-tls-proxy.hook maintains.
mkdir -p "$APPDIR"/share/ca-certificates
cp /work/ca-bundle.crt "$APPDIR"/share/ca-certificates/ca-bundle.crt
for f in "$APPDIR"/lib/libgnutls.so.*; do
	[ -f "$f" ] || continue
	python3 /work/tools/patch_gnutls_ca.py "$f"
done

# libsoup soup-tld public-suffix data: ALT hard-codes the path; patch libpsl
# and ship the .dafsa that 09-media-psl.hook symlinks to.
mkdir -p "$APPDIR"/share/publicsuffix
cp /work/public_suffix_list.dafsa "$APPDIR"/share/publicsuffix/public_suffix_list.dafsa
for f in "$APPDIR"/lib/libpsl.so.*; do
	[ -f "$f" ] || continue
	python3 /work/tools/patch_psl_path.py "$f"
done

# GStreamer elements WebKit needs (autoaudiosink / pulsesink) come from
# gst-plugins-good, which is not installed in the base ALT rootfs.
mkdir -p "$APPDIR"/lib/gstreamer-1.0
cp /work/shims/libgstautodetect.so /work/shims/libgstpulseaudio.so \
	"$APPDIR"/lib/gstreamer-1.0/

# Replace libEGL with the ANGLE/Maleoon hardware-accel shim. The libEGL.so.1
# symlink still targets libEGL.so.1.1.0, preserving the expected ABI.
cp /work/shims/libEGL.so.1.1.0 "$APPDIR"/lib/libEGL.so.1.1.0
chmod 755 "$APPDIR"/lib/libEGL.so.1.1.0

# Hard requirement: remove every other WebKit ABI before pruning.
rm -f "$APPDIR"/lib/libwebkitgtk-6.0.so* \
      "$APPDIR"/lib/libjavascriptcoregtk-6.0.so* \
      "$APPDIR"/lib/libwebkit2gtk-4.1.so* \
      "$APPDIR"/lib/libjavascriptcoregtk-4.1.so*
rm -rf "$APPDIR"/lib/webkitgtk-6.0 "$APPDIR"/lib/webkit2gtk-4.1

# Drop unreachable shared libraries (dlopen plugin dirs are preserved).
python3 /work/tools/prune_sos.py "$APPDIR" \
	--keep-list /work/telegram-runtime-libs.txt --apply > /work/prune.log

# Re-assert the shim after pruning (defensive: pruning never targets libEGL,
# but keep the payload byte-exact regardless).
cp /work/shims/libEGL.so.1.1.0 "$APPDIR"/lib/libEGL.so.1.1.0
chmod 755 "$APPDIR"/lib/libEGL.so.1.1.0

quick-sharun --make-appimage

# Sanity check: only 4.0 WebKit ABI and the exact shim in the final image.
find "$APPDIR"/lib -maxdepth 1 \( -iname '*webkit*' -o -iname '*javascriptcore*' \) \
	| grep -vE '4\.0' && { echo "ERROR: non-4.0 WebKit library found" >&2; exit 1; } || :
md5sum "$APPDIR"/lib/libEGL.so.1.1.0
echo "AppImage built at: $OUTPATH"

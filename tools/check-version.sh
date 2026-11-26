#!/bin/sh
# Determine the latest telegram-desktop version available in ALT Linux p11.
#
# Primary source: pkgs.org's ALT Linux page for telegram-desktop.
# Because pkgs.org serves a human-verification challenge (HTTP 402) to some
# IPs, fall back to the official ALT p11 aarch64 repository directory listing.
#
# Prints the version NVR (e.g. 7.4.4-alt1) on stdout and writes it to
# $GITHUB_OUTPUT (key: version) when running in Actions. Sets changed=true /
# false by comparing against LATEST_VERSION.
set -eu

REPO_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$REPO_ROOT"
UA='Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36'
MIRROR=${ALT_MIRROR:-https://ftp.altlinux.org/pub/distributions/ALTLinux}

extract_nvr() {
	# Accepts HTML or plain text; extracts a version from an RPM filename like
	# telegram-desktop-7.4.4-alt1.aarch64.rpm.
	grep -oE 'telegram-desktop-[0-9][^"<[:space:]]*\.aarch64\.rpm' \
		| sed 's/^telegram-desktop-//; s/\.aarch64\.rpm$//' \
		| grep -E '^[0-9].*-alt[0-9]+$' \
		| sort -V -u | tail -n 1 || true
}

VERSION=""
PKGURL="https://pkgs.org/download/telegram-desktop"

echo "check-version: trying pkgs.org ($PKGURL)" >&2
body=$(curl -fsSL --max-time 30 -A "$UA" "$PKGURL" 2>/dev/null || true)
if [ -n "$body" ] && ! printf '%s' "$body" | grep -qi "verify you're human"; then
	# pkgs.org links to per-package pages like
	# .../telegram-desktop-7.4.4-alt1-aarch64-rpm.html
	VERSION=$(printf '%s' "$body" \
		| grep -oE 'telegram-desktop-[0-9][0-9A-Za-z._+-]*-alt[0-9]+-aarch64-rpm\.html' \
		| sed -E 's/^telegram-desktop-//; s/-aarch64-rpm\.html$//' \
		| sort -V -u | tail -n 1 || true)
fi

if [ -z "$VERSION" ]; then
	echo "check-version: pkgs.org unavailable; falling back to ALT mirror" >&2
	body=$(curl -fsSL --max-time 30 \
		"$MIRROR/p11/branch/aarch64/RPMS.classic/" 2>/dev/null || true)
	VERSION=$(printf '%s' "$body" | extract_nvr || true)
fi

if [ -z "$VERSION" ]; then
	echo "check-version: ERROR could not determine ALT telegram version" >&2
	exit 1
fi

CURRENT=$(cat LATEST_VERSION)
echo "check-version: ALT=$VERSION local=$CURRENT"

CHANGED=false
if [ "$VERSION" != "$CURRENT" ]; then
	CHANGED=true
fi

echo "$VERSION"
if [ -n "${GITHUB_OUTPUT:-}" ]; then
	printf 'version=%s\nchanged=%s\n' "$VERSION" "$CHANGED" >> "$GITHUB_OUTPUT"
fi

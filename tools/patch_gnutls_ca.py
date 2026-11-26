#!/usr/bin/env python3
"""Patch ALT's libgnutls so its compiled-in CA trust path points at a /tmp
symlink the AppImage hook creates.

ALT p11 builds GnuTLS 3.8.13 with the trust store hard-coded to
/usr/share/ca-certificates/ca-bundle.crt. There is NO environment variable
(GNUTLS_SYSTEM_TRUST_STORE_FILE / SSL_CERT_FILE / SSL_CERT_DIR / G_TLS_CA_FILE
are all ignored by gnutls_x509_trust_list_add_system_trust), so on hosts that
only provide /etc/ssl/certs/ca-certificates.crt the trust list ends up empty
and WebKit mini-apps fail with "Unacceptable TLS certificate".

We rewrite that one path string in-place to /tmp/tgca-bundle.crt (shorter than
the original, so we NUL-pad); the 09-tls-proxy hook symlinks that path to the
CA bundle shipped inside the AppDir. This is the same /tmp-symlink technique
already used for the WebKit injected bundle and works because WebKit sandbox
is disabled in quick-sharun.

Usage: patch_gnutls_ca.py <libgnutls.so...> [more libs...]
"""
import sys

OLD = b"/usr/share/ca-certificates/ca-bundle.crt"
NEW = b"/tmp/tgca-bundle.crt"


def patch(path):
    with open(path, "rb") as f:
        data = bytearray(f.read())
    count = data.count(OLD)
    if count == 0:
        # Already patched or unexpected build; verify NEW is present.
        if NEW in data:
            print("already patched:", path, flush=True)
            return
        print("WARNING: trust path not found in", path, flush=True)
        return
    if len(NEW) > len(OLD):
        raise SystemExit("replacement longer than original; aborting")
    i = data.find(OLD)
    while i >= 0:
        data[i:i + len(OLD)] = NEW + b"\0" * (len(OLD) - len(NEW))
        i = data.find(OLD, i + len(NEW))
    with open(path, "wb") as f:
        f.write(data)
    print("patched %d occurrence(s): %s" % (count, path), flush=True)


if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if not args:
        raise SystemExit("usage: patch_gnutls_ca.py <libgnutls.so...>")
    for a in args:
        patch(a)

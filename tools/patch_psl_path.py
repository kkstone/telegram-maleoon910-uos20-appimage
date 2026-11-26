#!/usr/bin/env python3
"""Patch ALT's libpsl so its compiled-in public-suffix data path points at a
/tmp symlink the AppImage hook creates.

ALT p11's libpsl 0.21.5 hard-codes the public suffix list to
/usr/share/publicsuffix/public_suffix_list.dafsa and has NO environment
variable override (PSL_FILE etc. are ignored by psl_latest()). On hosts without
that file, libsoup logs:

    soup-tld: There is no public-suffix data available.

and cookie/domain checks break in WebKit mini-apps. Rewrite that one path
in-place to /tmp/tg-psl.dafsa (shorter, NUL-padded); the path-mapping hook
symlinks it to the .dafsa file shipped inside the AppDir.

Usage: patch_psl_path.py <libpsl.so...> [more libs...]
"""
import sys

OLD = b"/usr/share/publicsuffix/public_suffix_list.dafsa"
NEW = b"/tmp/tg-psl.dafsa"


def patch(path):
    with open(path, "rb") as f:
        data = bytearray(f.read())
    count = data.count(OLD)
    if count == 0:
        if NEW in data:
            print("already patched:", path, flush=True)
            return
        print("WARNING: psl data path not found in", path, flush=True)
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
        raise SystemExit("usage: patch_psl_path.py <libpsl.so...>")
    for a in args:
        patch(a)

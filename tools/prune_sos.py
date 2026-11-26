#!/usr/bin/env python3
"""Remove unreachable shared libraries from an AppDir.

Builds a DT_NEEDED reachability graph from the main executables plus every ELF
file in dlopen-style plugin directories. Libraries that are dlopened by name
(glibc NSS, Mesa/GL drivers, sharun preload, etc.) are kept via whitelists.

Usage:
  prune_sos.py <AppDir> [--apply]
Without --apply it only reports what would be removed.
"""
import os
import re
import struct
import sys
from collections import defaultdict, deque

APPDIR = os.path.abspath(sys.argv[1])
APPLY = "--apply" in sys.argv[2:]
KEEP_FILE = None
if "--keep-list" in sys.argv[2:]:
    KEEP_FILE = sys.argv[sys.argv.index("--keep-list") + 1]
KEEP_NAMES = set()
if KEEP_FILE:
    with open(KEEP_FILE, encoding="utf-8") as f:
        KEEP_NAMES = {line.strip() for line in f if line.strip() and not line.startswith("#")}

DLOPEN_DIRS = [
    "lib/qt6/plugins", "lib/qt6/qml", "lib/gstreamer-1.0", "lib/gconv",
    "lib/webkit2gtk-4.0", "lib/webkit2gtk-4.0/injected-bundle",
    "lib/webkitgtk-6.0", "lib/webkit2gtk-4.1",
    "lib/spa-0.2", "lib/pipewire-0.3", "lib/alsa-lib", "lib/pulseaudio",
    "lib/gbm", "lib/dri", "lib/gdk-pixbuf-2.0", "lib/gio/modules",
    "lib/gtk-3.0", "lib/gtk-4.0", "lib/libheif", "lib/proxy",
    "lib/samba", "lib/pkcs11", "lib/sharun-preload", "lib/vdpau",
    "lib/llvm-21.1/lib64", "lib/bin",
]

ROOT_FILES = [
    "sharun", "dash", "bin/Telegram", "bin/bwrap",
    "bin/WebKitWebProcess", "bin/WebKitNetworkProcess", "bin/WebKitGPUProcess",
]

# Top-level libraries loaded by dlopen/absolute rewritten paths rather than
# DT_NEEDED, or required by the dynamic loader itself.
KEEP_NAME_PATTERNS = [
    r"^ld-linux", r"^libc\.", r"^libpthread", r"^libdl\.", r"^librt\.",
    r"^libm\.", r"^libgcc_s", r"^libstdc\+\+", r"^libnss_", r"^libnsl",
    r"^libresolv", r"^libsharun", r"^libgallium", r"^libLLVM",
    r"^libGL", r"^libEGL", r"^libOSMesa", r"^libvulkan", r"^libgbm",
    r"^libva", r"^libdrm", r"^libffi", r"^libz\.", r"^libzstd",
    r"^liblzma", r"^libbz2", r"^libexpat", r"^libsqlite3",
]

NEEDED_RE = re.compile(r"\(NEEDED\)\s+\[([^\]]+)\]")
SONAME_RE = re.compile(r"\(SONAME\)\s+\[([^\]]+)\]")


def read_dyn(path):
    """Return (DT_NEEDED list, DT_SONAME) using a minimal ELF64 parser.
    Avoids depending on readelf inside the build rootfs."""
    try:
        with open(path, "rb") as f:
            data = f.read()
    except OSError:
        return [], None
    if len(data) < 64 or data[:4] != b"\x7fELF" or data[4] != 2:
        return [], None  # only ELF64
    if data[5] != 1:
        return [], None  # only little-endian
    try:
        shoff = struct.unpack_from("<Q", data, 0x28)[0]
        shentsize = struct.unpack_from("<H", data, 0x3A)[0]
        shnum = struct.unpack_from("<H", data, 0x3C)[0]
        shstrndx = struct.unpack_from("<H", data, 0x3E)[0]
        if not shoff or not shentsize or shnum > 4096:
            return [], None
        sections = []
        for i in range(shnum):
            off = shoff + i * shentsize
            if off + 64 > len(data):
                return [], None
            sh_type = struct.unpack_from("<I", data, off + 4)[0]
            sh_offset = struct.unpack_from("<Q", data, off + 0x18)[0]
            sh_size = struct.unpack_from("<Q", data, off + 0x20)[0]
            sh_link = struct.unpack_from("<I", data, off + 0x28)[0]
            sections.append((sh_type, sh_offset, sh_size, sh_link))
        if shstrndx >= len(sections):
            return [], None
        dynamic = next((s for s in sections if s[0] == 6), None)
        if dynamic is None:
            return [], None
        strtab_off, strtab_size = sections[dynamic[3]][1], sections[dynamic[3]][2]
        strtab = data[strtab_off:strtab_off + strtab_size]

        def getstr(idx):
            end = strtab.find(b"\0", idx)
            if end < 0:
                end = len(strtab)
            return strtab[idx:end].decode("utf-8", "replace")

        needed, soname = [], None
        off, size = dynamic[1], dynamic[2]
        for pos in range(off, off + size - 15, 16):
            tag, val = struct.unpack_from("<QQ", data, pos)
            if tag == 1:      # DT_NEEDED
                needed.append(getstr(val))
            elif tag == 14:   # DT_SONAME
                soname = getstr(val)
            elif tag == 0:    # DT_NULL
                break
        return needed, soname
    except (struct.error, IndexError, ValueError):
        return [], None


def main():
    libdir = os.path.join(APPDIR, "lib")
    so_files = []
    for root, dirs, files in os.walk(libdir):
        for name in files:
            if ".so" in name:
                so_files.append(os.path.join(root, name))

    real_files = [p for p in so_files if not os.path.islink(p)]
    symlinks = [p for p in so_files if os.path.islink(p)]

    soname_map = defaultdict(list)
    base_map = defaultdict(list)
    for p in real_files:
        needed, soname = read_dyn(p)
        key = soname or os.path.basename(p)
        soname_map[key].append(p)
        base_map[os.path.basename(p)].append(p)
        # versioned basename: libfoo.so.1.2.3 also answers to libfoo.so.1
        m = re.match(r"^(.*\.so\.\d+)", os.path.basename(p))
        if m:
            base_map[m.group(1)].append(p)

    symlinks_by_target = defaultdict(list)
    for p in symlinks:
        symlinks_by_target[os.path.realpath(p)].append(p)

    def resolve(needed):
        found = set(soname_map.get(needed, []))
        found |= set(base_map.get(needed, []))
        for key in base_map:
            if key.startswith(needed + "."):
                found |= set(base_map[key])
        for real in list(found):
            found |= set(symlinks_by_target.get(real, []))
        return found

    reachable = set()

    def add_root(path):
        if os.path.exists(path):
            reachable.add(os.path.realpath(path))

    for rel in ROOT_FILES:
        add_root(os.path.join(APPDIR, rel))
    for rel in DLOPEN_DIRS:
        d = os.path.join(APPDIR, rel)
        if not os.path.isdir(d):
            continue
        for root, _, files in os.walk(d):
            for name in files:
                p = os.path.join(root, name)
                if os.path.islink(p):
                    reachable.add(os.path.realpath(p))
                else:
                    add_root(p)

    for name in os.listdir(libdir):
        if any(re.match(pat, name) for pat in KEEP_NAME_PATTERNS) or \
           name.startswith(("libwebkit", "libjavascriptcore", "libsoup")) or \
           name in KEEP_NAMES:
            p = os.path.join(libdir, name)
            if os.path.islink(p):
                reachable.add(os.path.realpath(p))
            else:
                reachable.add(p)

    q = deque(reachable)
    while q:
        p = q.popleft()
        needed, _ = read_dyn(p)
        for soname in needed:
            for hit in resolve(soname):
                real = os.path.realpath(hit)
                if real not in reachable:
                    reachable.add(real)
                    q.append(real)

    protected_dirs = tuple(os.path.join(APPDIR, d) + os.sep for d in DLOPEN_DIRS)

    # A dlopen-style plugin whose own NEEDED entries cannot be satisfied by the
    # bundle can never load. Drop it too, otherwise it stays behind as dead
    # weight inside plugin directories.
    all_sonames = set()
    for d, _, files in os.walk(libdir):
        for name in files:
            if ".so" in name:
                all_sonames.add(name)

    def basic_dep(dep):
        return dep.startswith(("libgcc_", "libc.so", "libm.so", "ld-linux",
                               "libpthread", "libdl", "librt", "libresolv"))

    broken_plugins = []
    for d in DLOPEN_DIRS:
        base = os.path.join(APPDIR, d)
        if not os.path.isdir(base):
            continue
        for root, _, files in os.walk(base):
            for name in files:
                p = os.path.join(root, name)
                if os.path.islink(p) or ".so" not in name:
                    continue
                needed = read_dyn(p)[0]
                if not needed:
                    continue
                if any(not basic_dep(x) and not any(
                        s == x or s.startswith(x + ".") for s in all_sonames
                ) for x in needed):
                    broken_plugins.append(p)
    print(f"Unloadable plugin ELFs: {len(broken_plugins)}")

    to_remove = list(broken_plugins)
    for p in so_files:
        real = os.path.realpath(p)
        if real in reachable:
            continue
        if p.startswith(protected_dirs):
            continue
        name = os.path.basename(p)
        if any(re.match(pat, name) for pat in KEEP_NAME_PATTERNS):
            continue
        if name in KEEP_NAMES:
            continue
        to_remove.append(p)

    total = 0
    for p in to_remove:
        try:
            total += os.path.getsize(p) if not os.path.islink(p) else 0
        except OSError:
            pass
    print(f"AppDir: {APPDIR}")
    print(f"ELF .so files scanned: {len(so_files)}")
    print(f"Reachable real files: {len([p for p in reachable if os.path.isfile(p)])}")
    print(f"Unreachable .so entries: {len(to_remove)} ({total/1024/1024:.1f} MiB)")
    for p in sorted(to_remove):
        print("  " + os.path.relpath(p, APPDIR))
    if APPLY:
        for p in to_remove:
            try:
                os.remove(p)
            except OSError as e:
                print(f"FAILED {p}: {e}", file=sys.stderr)
        print("Removed unreachable .so entries.")


if __name__ == "__main__":
    main()

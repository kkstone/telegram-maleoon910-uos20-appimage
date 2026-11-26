#!/usr/bin/env python3
"""Resolve the full apt dependency closure for telegram-desktop in the ALT rootfs.
Runs on the HOST; invokes apt-cache via alt.sh (bwrap). Emits RPM filenames."""
import subprocess
import re
import sys
import glob
import os
from collections import deque

import os as _os
BASE = _os.environ.get("REPO_ROOT", _os.getcwd())
ALT = f"{BASE}/tools/alt.sh"
RPMDB = f"{BASE}/alt-rootfs/var/lib/rpm"

_call_count = 0

def apt_cache(*args):
    global _call_count
    _call_count += 1
    # db4 lock files can get stuck under bwrap; clear stale ones periodically
    if _call_count % 25 == 1:
        for f in glob.glob(f"{RPMDB}/__db.*"):
            try: os.remove(f)
            except OSError: pass
    cmd = [ALT, "/bin/bash", "-lc", "export LC_ALL=C LANG=C; apt-cache " + " ".join(args)]
    r = subprocess.run(cmd, capture_output=True, text=True)
    out = "\n".join(l for l in r.stdout.splitlines() if "setlocale" not in l)
    # retry once on rpmdb lock error
    if "could not open RPM database" in out or "dbenv->open" in r.stderr:
        for f in glob.glob(f"{RPMDB}/__db.*"):
            try: os.remove(f)
            except OSError: pass
        r = subprocess.run(cmd, capture_output=True, text=True)
        out = "\n".join(l for l in r.stdout.splitlines() if "setlocale" not in l)
    return out

NVR_RE = re.compile(r"^([a-zA-Z0-9._+\-]+?)-[0-9][0-9a-zA-Z._+]*-alt\d+")

def pkg_base(nvr):
    """Extract base package name from an NVR string (strip version-release-epoch)."""
    s = nvr.strip().split()[0]
    if ":p11" in s:
        s = s.split(":p11")[0]
    # NVR like libqt6-core-6.11.2-alt2
    m = NVR_RE.match(s)
    if m:
        return m.group(1)
    # NVR like glibc-core-6:2.38...  (epoch with colon, package has trailing -6)
    m = re.match(r"^([a-zA-Z0-9._+\-]+?):[0-9]", s)
    if m:
        return m.group(1)
    return s

def get_dep_nvrs(pkg):
    """Return list of NVR/base names for all real providers in depends output."""
    out = apt_cache("depends", pkg)
    lines = out.splitlines()
    result = []
    for line in lines:
        stripped = line.strip()
        # provider lines: 4 spaces indentation, no 'Depends:', not virtual
        if line.startswith("    ") and not stripped.startswith("<") and not stripped.startswith("Depends"):
            result.append(stripped)
            continue
        m = re.match(r"\s*(Depends|PreDepends):\s*(.*)", line)
        if not m:
            continue
        dep = m.group(2).strip()
        if dep.startswith("<"):
            continue  # virtual, provider handled by indented line
        # non-virtual dep like "libqt6-core = 6.11.2" or "dbus"
        dep = dep.split("=")[0].split("<")[0].strip()
        if dep:
            result.append(dep)
    return result

def _show_filename(query):
    out = apt_cache("show", query)
    for line in out.splitlines():
        if line.startswith("Filename:"):
            return line.split(":", 1)[1].strip()
    return None

def get_filename(query):
    """Try the name as-is, then progressively strip trailing -N version tags."""
    fn = _show_filename(query)
    if fn:
        return fn
    # Virtual names like libX11-3 / libxml2-1 / libjpeg-2: strip trailing -digits
    parts = query.split("-")
    while len(parts) > 1 and re.fullmatch(r"\d+", parts[-1]):
        parts = parts[:-1]
        cand = "-".join(parts)
        fn = _show_filename(cand)
        if fn:
            return fn
    return None

def main():
    roots = sys.argv[1:] or ["telegram-desktop"]
    seen, q, pkgs = set(), deque(roots), set()
    while q:
        query = q.popleft()
        # Resolve to a real package name + filename first
        fn = get_filename(query)
        if not fn or not fn.endswith(".rpm"):
            print(f"WARN no filename: query={query!r}", file=sys.stderr)
            continue
        # Use the resolved real package name (from filename) as visited key
        real = fn.rsplit("-", 2)[0]  # strip -version-release.aarch64.rpm
        if real in seen:
            continue
        seen.add(real)
        pkgs.add(fn)
        for dep_query in get_dep_nvrs(query):
            if dep_query and dep_query not in seen:
                q.append(dep_query)
    for fn in sorted(pkgs):
        print(fn)
    print(f"# total RPMs: {len(pkgs)}, packages visited: {len(seen)}", file=sys.stderr)

if __name__ == "__main__":
    main()

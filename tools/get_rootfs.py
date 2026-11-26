#!/usr/bin/env python3
"""Pull the aarch64 image used by the project CI into a plain rootfs directory."""
import copy
import json
import os
import shutil
import sys
import tarfile
import urllib.request

REPO = "pkgforge-dev/archlinux"
ROOTFS = sys.argv[1] if len(sys.argv) > 1 else "arch-rootfs"


def ghcr_get(url, token, accept=None):
    headers = {"Authorization": f"Bearer {token}"}
    if accept:
        headers["Accept"] = accept
    req = urllib.request.Request(url, headers=headers)
    return urllib.request.urlopen(req, timeout=120)


token = json.load(urllib.request.urlopen(
    f"https://ghcr.io/token?scope=repository:{REPO}:pull&service=ghcr.io", timeout=60))["token"]

index = json.load(ghcr_get(f"https://ghcr.io/v2/{REPO}/manifests/latest", token,
                           "application/vnd.oci.image.index.v1+json"))
digests = [m["digest"] for m in index["manifests"]
           if m.get("platform", {}).get("architecture") == "arm64"
           and "attestation" not in m.get("annotations", {}).get("vnd.docker.reference.type", "")]
assert digests, "no arm64 manifest"
manifest = json.load(ghcr_get(f"https://ghcr.io/v2/{REPO}/manifests/{digests[0]}", token,
                              "application/vnd.oci.image.manifest.v1+json"))
print("manifest:", digests[0], flush=True)

os.makedirs(ROOTFS, exist_ok=True)


def safe_filter(member, dest):
    if member.isdev() or member.isfifo():
        return None
    m = copy.copy(member)
    if (m.issym() or m.islnk()) and os.path.isabs(m.linkname):
        base = "/" + os.path.dirname(m.name)
        m.linkname = os.path.relpath(m.linkname, base)
    return tarfile.data_filter(m, dest)


for i, layer in enumerate(manifest["layers"]):
    digest = layer["digest"]
    print(f"layer {i + 1}/{len(manifest['layers'])} {layer['size']/1e6:.1f} MB", flush=True)
    tmp = f"/tmp/layer-{digest.replace(':', '-')}.tar.gz"
    if not (os.path.exists(tmp) and os.path.getsize(tmp) == layer["size"]):
        with ghcr_get(f"https://ghcr.io/v2/{REPO}/blobs/{digest}", token) as r, open(tmp, "wb") as f:
            shutil.copyfileobj(r, f, length=1024 * 1024)
    with tarfile.open(tmp, "r:gz") as tar:
        names = tar.getnames()
        for name in names:
            parts = name.split("/.wh.")
            if len(parts) == 2:
                target = os.path.join(ROOTFS, parts[0], parts[1])
                print("  whiteout:", target, flush=True)
                if os.path.isdir(target) and not os.path.islink(target):
                    shutil.rmtree(target, ignore_errors=True)
                elif os.path.lexists(target):
                    os.unlink(target)
        tar.extractall(ROOTFS, filter=safe_filter)
    os.unlink(tmp)

print("rootfs ready:", os.path.abspath(ROOTFS), flush=True)

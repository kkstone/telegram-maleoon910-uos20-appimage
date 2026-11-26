#!/bin/sh
# Run a command inside the frozen ALT Linux p11 aarch64 rootfs.
#
# Two execution modes, picked automatically:
#   * root (CI container / sudo) -> chroot into alt-rootfs. No user namespaces,
#     which GitHub-hosted runners do not allow.
#   * unprivileged (local dev)   -> bwrap with a uid map, so no root needed.
#
# The repository is made available at /work in both modes.
BASE=${REPO_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}
ROOTFS="$BASE/alt-rootfs"
[ -d "$ROOTFS/usr" ] || { echo "ERROR: $ROOTFS is not a populated ALT rootfs (run get-dependencies.sh first)" >&2; exit 1; }

if [ "$(id -u)" = "0" ]; then
  # ---- root mode: chroot (CI-friendly, no user namespace needed) ----
  mkdir -p "$ROOTFS/work" "$ROOTFS/proc" "$ROOTFS/dev" "$ROOTFS/sys"
  # Bind mounts are best-effort; if the runner forbids them, chroot still works
  # for the build as long as /proc and /dev are already usable inside rootfs.
  mount --bind /proc "$ROOTFS/proc" 2>/dev/null || :
  mount --bind /dev "$ROOTFS/dev" 2>/dev/null || :
  mount --bind /sys "$ROOTFS/sys" 2>/dev/null || :
  mount --bind "$BASE" "$ROOTFS/work" 2>/dev/null || :
  [ -f /etc/resolv.conf ] && mount --bind /etc/resolv.conf "$ROOTFS/etc/resolv.conf" 2>/dev/null || :
  exec chroot "$ROOTFS" /bin/sh -c 'cd /work && exec "$@"' sh "$@"
else
  # ---- unprivileged mode: bubblewrap (local development) ----
  exec bwrap                                              \
    --unshare-user --unshare-pid --uid 0 --gid 0          \
    --bind "$ROOTFS" /                                    \
    --bind "$BASE" /work                                  \
    --proc /proc --dev /dev                               \
    --bind /etc/resolv.conf /etc/resolv.conf              \
    --setenv PATH /usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    --chdir /work                                         \
    "$@"
fi

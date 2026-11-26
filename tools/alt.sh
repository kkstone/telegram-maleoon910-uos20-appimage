#!/bin/sh
# Run commands inside a pure ALT Linux p11 aarch64 rootfs.
BASE=${REPO_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}
exec bwrap                                              \
  --unshare-user --unshare-pid --uid 0 --gid 0          \
  --bind "$BASE/alt-rootfs" /                           \
  --bind "$BASE" /work                                  \
  --proc /proc --dev /dev                               \
  --bind /etc/resolv.conf /etc/resolv.conf              \
  --setenv PATH /usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
  --chdir /work                                         \
  "$@"

#!/bin/sh
# Run commands inside a pure ALT Linux p11 aarch64 rootfs.
BASE=${REPO_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}

# bwrap needs a user namespace for --uid/--gid mapping. GitHub-hosted runners
# disable unprivileged user namespaces, so when we run as root (the CI build
# uses sudo) there is no need to map uids at all: root already is uid 0.
# Detect this at runtime and pick the matching bwrap flags.
if [ "$(id -u)" = "0" ]; then
  # No --unshare-user: avoids "setting up uid map: Permission denied" on
  # runners with user namespaces disabled. We are already uid 0.
  set -- \
    --bind "$BASE/alt-rootfs" /                         \
    --bind "$BASE" /work                                \
    --proc /proc --dev /dev                             \
    --bind /etc/resolv.conf /etc/resolv.conf            \
    --setenv PATH /usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    --chdir /work                                       \
    "$@"
else
  set -- \
    --unshare-user --unshare-pid --uid 0 --gid 0        \
    --bind "$BASE/alt-rootfs" /                         \
    --bind "$BASE" /work                                \
    --proc /proc --dev /dev                             \
    --bind /etc/resolv.conf /etc/resolv.conf            \
    --setenv PATH /usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    --chdir /work                                       \
    "$@"
fi
exec bwrap "$@"

#!/bin/sh
# Run commands inside the project's Arch Linux ARM container rootfs.
BASE=/home/UOS/WorkBuddy/2026-11-25-15-49-34/Telegram-AppImage
exec bwrap                                              \
  --unshare-user --unshare-pid --uid 0 --gid 0          \
  --bind "$BASE/arch-rootfs" /                          \
  --bind "$BASE" /work                                  \
  --proc /proc --dev /dev                               \
  --bind /etc/resolv.conf /etc/resolv.conf              \
  --setenv PATH /usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
  --chdir /work                                         \
  "$@"

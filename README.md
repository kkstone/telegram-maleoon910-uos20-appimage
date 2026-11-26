<div align="center">

# Telegram AppImage — ALT p11 / Maleoon 910 / UOS20 🐧

[![CI Build Status](https://github.com/kkstone/telegram-maleoon910-uos20-appimage/actions/workflows/appimage.yml/badge.svg)](https://github.com/kkstone/telegram-maleoon910-uos20-appimage/actions/workflows/appimage.yml)
[![Latest Stable Release](https://img.shields.io/github/v/release/kkstone/telegram-maleoon910-uos20-appimage)](https://github.com/kkstone/telegram-maleoon910-uos20-appimage/releases/latest)

<p align="center">
  <img src="https://raw.githubusercontent.com/telegramdesktop/tdesktop/refs/heads/dev/Telegram/Resources/art/icon128.png" width="128" />
</p>

| Latest Release | Upstream | Build base |
| :---: | :---: | :---: |
| [Releases](https://github.com/kkstone/telegram-maleoon910-uos20-appimage/releases/latest) | [telegramdesktop/tdesktop](https://github.com/telegramdesktop/tdesktop) | ALT Linux p11 |

**aarch64 only. WebKit2GTK-4.0 only — no 6.0 / 4.1 stacks bundled.**

</div>

---

## What this is

A fork of the [pkgforge-dev/Telegram-AppImage](https://github.com/pkgforge-dev/Telegram-AppImage) build recipe, adapted for:

- **aarch64** hosts running UOS 20 / other ARM64 Linux.
- **Maleoon 910** hardware acceleration (ANGLE → Vulkan), including WebView mini-apps.
- Libraries taken **entirely from ALT Linux p11** so there are no cross-distro ABI conflicts.

The AppImage is built with [sharun](https://github.com/VHSgunzo/sharun) and
[quick-sharun](https://github.com/pkgforge-dev/Anylinux-AppImages/blob/main/useful-tools/quick-sharun.sh).
It bundles its own libs and needs no FUSE (uruntime) and no container at runtime.

## Hardware acceleration — IMPORTANT

The AppImage's `lib/libEGL.so.1.1.0` is an **ANGLE shim**, not Mesa's EGL. It
loads the real ANGLE/Vulkan libraries from the host at runtime:

```
egl*() → in-AppImage libEGL.so.1.1.0 (shim)
       → /opt/telegram/lib/angle/libEGL.so + libGLESv2.so
       → /opt/telegram/lib/libvulkan.so.1
       → /opt/telegram/lib/icd/icd-wrap.so
       → /usr/lib/aarch64-linux-gnu/libhvgr.so  (Maleoon driver, system-provided)
```

Therefore **you must install the companion deb before launching the AppImage**:

```sh
sudo dpkg -i telegram-desktop-hwaccel_7.4.4-1_arm64.deb
```

The deb is shipped in [`assets/`](assets/) and attached to every GitHub Release.
It installs the ANGLE libraries under `/opt/telegram/lib` and a `Telegram`
launcher. It does **not** replace the AppImage — run the AppImage as usual after
installing the deb.

Requirements: aarch64 + Maleoon 910 GPU + a system `libhvgr.so`. Without these,
the shim falls back gracefully but hardware acceleration will not work.

## Build from source

Everything is built natively on aarch64 inside an ALT Linux p11 rootfs.

```sh
sh ./get-dependencies.sh     # bootstrap ALT rootfs + resolve/download RPMs
./tools/alt.sh sh -c 'export LC_ALL=C; /work/make-appimage.sh'
```

`get-dependencies.sh` downloads the minimal ALT p11 rootfs, fetches the
aarch64 + noarch package indexes, resolves the full dependency closure of
Telegram and WebKit2GTK-4.0, and installs the RPMs. `make-appimage.sh` then
assembles only the 4.0 WebKit ABI, applies the GnuTLS CA / libpsl public-suffix
/ GStreamer / DPI-cursor / audio fixes, swaps in the EGL shim, and produces the
AppImage in `dist/`.

## Automated updates

[`.github/workflows/appimage.yml`](.github/workflows/appimage.yml) runs daily at
**02:30 UTC+8** (cron `30 18 * * *` UTC). It checks
[pkgs.org](https://pkgs.org/download/telegram-desktop) for the latest
`telegram-desktop` version in ALT Linux p11, with a fallback to the official
ALT mirror directory listing when pkgs.org serves a human-verification
challenge. If the version differs from [`LATEST_VERSION`](LATEST_VERSION), it
builds a fresh AppImage, publishes it (plus the deb) to a GitHub Release, and
updates `LATEST_VERSION`. You can also trigger a build manually with
`workflow_dispatch`.

## Credits

- [pkgforge-dev/Telegram-AppImage](https://github.com/pkgforge-dev/Telegram-AppImage) — original build recipe.
- [VHSgunzo/sharun](https://github.com/VHSgunzo/sharun), [quick-sharun](https://github.com/pkgforge-dev/Anylinux-AppImages) — portability layer.
- ALT Linux p11 — library stack.

Licensed under MIT (see [LICENSE](LICENSE)).

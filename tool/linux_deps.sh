#!/usr/bin/env bash
# Download and extract the Linux runtime libraries required by media_kit's
# bundled libmpv without root. Prints the library directory on stdout.
set -euo pipefail

CACHE="${SAKUGA_LINUX_DEPS:-$HOME/.cache/sakuga/linux-deps}"
DEBS="$CACHE/debs"
ROOT="$CACHE/root"
ARCH="$(dpkg --print-architecture)"
case "$ARCH" in
  amd64) MULTIARCH="x86_64-linux-gnu" ;;
  arm64) MULTIARCH="aarch64-linux-gnu" ;;
  *) MULTIARCH="$ARCH-linux-gnu" ;;
esac
LIBDIR="$ROOT/usr/lib/$MULTIARCH"

mkdir -p "$DEBS" "$ROOT"

packages=(
  libva2 libva-drm2 libva-x11-2 libva-wayland2 libvdpau1
  libpulse0 libsndfile1 libasyncns0 libxss1 libxv1
  libflac12t64 libflac12 libmpg123-0t64 libmpg123-0
  libmp3lame0 libvorbis0a libvorbisenc2 libopus0 libogg0
)

for package in "${packages[@]}"; do
  if ! compgen -G "$DEBS/${package}_*.deb" >/dev/null; then
    if apt-cache show "$package" 2>/dev/null | grep -q '^Package:'; then
      (cd "$DEBS" && apt-get download "$package" >&2) || true
    fi
  fi
done

for deb in "$DEBS"/*.deb; do
  [ -e "$deb" ] || continue
  dpkg-deb -x "$deb" "$ROOT"
done

printf '%s\n' "$LIBDIR" "$LIBDIR/pulseaudio"

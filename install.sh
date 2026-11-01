#!/bin/bash
# Install launchers that run other phone shells in a window on Phosh.
# Usage: ./install.sh [--dry-run] [plasma] [lomiri] [ztmetro]
set -euo pipefail
ZTOS_COMMIT=fbb28e50cf65a6a0dbd88fc55075d2803d115d3e
WLROOTS_TAG=0.20.2
HERE=$(cd "$(dirname "$0")" && pwd)
STATE=$HOME/.local/share/nested-shells
DRY=0; WANT=()
for a in "$@"; do case $a in
  --dry-run) DRY=1 ;;
  plasma|lomiri|ztmetro) WANT+=("$a") ;;
  *) echo "Usage: $0 [--dry-run] [plasma] [lomiri] [ztmetro]"; exit 2 ;;
esac; done

CODENAME=$(cat /usr/lib/furios/device/codename 2>/dev/null || true)
if [ "$CODENAME" != radon ]; then
  echo "Only tested on the FLX1s (radon). This device: '${CODENAME:-unknown}'. Stopping."; exit 1
fi
pgrep -x phosh >/dev/null || { echo "Phosh isn't running. Stopping."; exit 1; }

if [ ${#WANT[@]} -eq 0 ]; then
  echo "Which shells? Plasma and Lomiri come from apt. ztMETRO is built on the phone and is experimental."
  read -rp "Plasma Mobile [y/N] " a; [[ $a == [yY]* ]] && WANT+=(plasma)
  read -rp "Lomiri [y/N] " a;        [[ $a == [yY]* ]] && WANT+=(lomiri)
  read -rp "ztMETRO [y/N] " a;       [[ $a == [yY]* ]] && WANT+=(ztmetro)
  [ ${#WANT[@]} -gt 0 ] || { echo "Nothing chosen."; exit 0; }
fi

PKGS=()
for s in "${WANT[@]}"; do case $s in
  plasma)  PKGS+=(plasma-mobile qt6-svg-plugins mesa-vulkan-drivers wlr-randr) ;;
  lomiri)  PKGS+=(lomiri mir-platform-graphics-wayland wlr-randr) ;;
  ztmetro) PKGS+=(git patch build-essential pkgconf meson ninja-build glslang-tools wlr-randr
             libwlroots-0.20-dev libwayland-dev wayland-protocols libxkbcommon-dev libcairo2-dev
             libpango1.0-dev librsvg2-dev libgdk-pixbuf-2.0-dev libpixman-1-dev libdrm-dev
             libegl-dev libgles-dev libjson-c-dev) ;;
esac; done

SIM=$(apt-get -s install --no-install-recommends "${PKGS[@]}")
NEW=$(awk '/^Inst /{print $2}' <<<"$SIM" | sort -u)
REMOVED=$(awk '/^Remv /{print $2}' <<<"$SIM")
if [ -n "$REMOVED" ]; then echo "apt would remove these, so stopping:"; echo "$REMOVED"; exit 1; fi
echo "Installing for: ${WANT[*]}"
echo "New packages: $(wc -w <<<"$NEW")"
if [ "$DRY" = 1 ]; then echo "$NEW" | tr '\n' ' '; echo; echo "Dry run: nothing changed."; exit 0; fi
echo "Use a spare Bootman install: this adds a lot and is hard to undo completely."
read -rp "Continue? [y/N] " a; [[ $a == [yY]* ]] || exit 0

mkdir -p "$STATE" ~/.local/bin ~/.local/share/applications ~/.local/share/icons/hicolor/scalable/apps
# Recorded first, so uninstall.sh knows what this added even if a later step fails.
[ -z "$NEW" ] || echo "$NEW" >> "$STATE/added-packages"
sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${PKGS[@]}"

build_ztmetro() {
  local root=$HOME/src/ztos n=$HOME/src/ztos/build/nested tmp
  tmp=$(mktemp -d); mkdir -p "$root" "$n/bin"
  git -C "$tmp" init -q
  git -C "$tmp" remote add origin https://github.com/Zerone-Laboratories/ztOS.git
  git -C "$tmp" fetch -q --depth 1 origin "$ZTOS_COMMIT"
  git -C "$tmp" checkout -q FETCH_HEAD
  rm -rf "$root/ztmetro" "$root/os" "$root/wlroots-0.20" "$root/build/wl-build" "$root/build/wlroots"
  mkdir -p "$root/os/overlay/etc" "$root/os/overlay/usr/local/share"
  cp -a "$tmp/ztmetro" "$root/"
  cp -a "$tmp/os/overlay/etc/skel" "$root/os/overlay/etc/"
  cp -a "$tmp/os/overlay/usr/local/share/fonts" "$root/os/overlay/usr/local/share/"
  rm -rf "$tmp"
  git clone -q --depth 1 --branch "$WLROOTS_TAG" https://gitlab.freedesktop.org/wlroots/wlroots.git "$root/wlroots-0.20"
  patch -d "$root/wlroots-0.20" -p1 < "$HERE/ztmetro-patches/wlroots-0.20.2-shm-render.patch"
  patch -d "$root/ztmetro" -p1 < "$HERE/ztmetro-patches/ztmetro-shm-readback.patch"
  patch -d "$root/ztmetro" -p1 < "$HERE/ztmetro-patches/ztsettings-flx1s-strings.patch"
  (cd "$root/wlroots-0.20" && meson setup "$root/build/wl-build" --prefix="$root/build/wlroots" \
    -Dbackends= -Dxwayland=disabled -Drenderers=gles2 -Dallocators= -Dsession=disabled -Dexamples=false)
  ninja -C "$root/build/wl-build" install
  export PKG_CONFIG_PATH=$root/build/wlroots/lib/aarch64-linux-gnu/pkgconfig
  make -C "$root/ztmetro" ztmetro
  local a
  for a in apps/ztapps settings/ztsettings contacts/ztcontacts files/ztfiles sound/ztsound; do
    if make -C "$root/ztmetro" "$a"; then ln -sf "$root/ztmetro/$a" "$n/bin/"
    else echo "Warning: $a didn't build, its tile won't open."; fi
  done
  if [ ! -d "$n/home" ]; then
    mkdir -p "$n/home/.local/share/fonts"
    cp -a "$root/os/overlay/etc/skel/." "$n/home/"
    ln -s "$root/os/overlay/usr/local/share/fonts" "$n/home/.local/share/fonts/ztos"
  fi
}

install -m755 "$HERE/nested-common" "$HERE/nested-restore-scale" ~/.local/bin/
for s in "${WANT[@]}"; do
  [ "$s" != ztmetro ] || build_ztmetro
  install -m755 "$HERE/nested-$s" ~/.local/bin/
  sed "s#^Exec=.*#Exec=$HOME/.local/bin/nested-$s#" "$HERE/nested-$s.desktop" > ~/.local/share/applications/nested-$s.desktop
  install -m644 "$HERE/nested-$s.svg" ~/.local/share/icons/hicolor/scalable/apps/
done
update-desktop-database ~/.local/share/applications 2>/dev/null || true
gtk-update-icon-cache -q ~/.local/share/icons/hicolor 2>/dev/null || true
echo "Done. Look for '(window)' in the app list. Tap an icon to open a shell, tap it again to close it."

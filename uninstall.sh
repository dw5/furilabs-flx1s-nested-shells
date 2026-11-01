#!/bin/bash
# Remove the launchers and the ztMETRO build, then offer to remove the added packages.
set -uo pipefail
STATE=$HOME/.local/share/nested-shells

for s in plasmashell kwin_wayland ztmetro; do pkill -x "$s"; done; pkill -9 -x lomiri
sleep 2
for s in plasma lomiri ztmetro; do
  rm -f ~/.local/bin/nested-$s ~/.local/share/applications/nested-$s.desktop \
    ~/.local/share/icons/hicolor/scalable/apps/nested-$s.svg
done
rm -f ~/.local/bin/nested-common ~/.local/bin/nested-restore-scale
rm -rf ~/src/ztos ~/.cache/nest-vulkan ~/.cache/nest-lomiri
update-desktop-database ~/.local/share/applications 2>/dev/null || true
echo "Launchers and build removed."

if [ ! -s "$STATE/added-packages" ]; then echo "No package list found."; exit 0; fi
mapfile -t PKGS < <(sort -u "$STATE/added-packages")
OUT=$(apt-get -s remove "${PKGS[@]}" 2>&1)
EXTRA=$(awk '/^Remv /{print $2}' <<<"$OUT" | sort -u | comm -23 - <(printf '%s\n' "${PKGS[@]}"))
echo "Packages this added: ${#PKGS[@]}"
if [ -n "$EXTRA" ]; then
  echo "Removing them would also remove these, so leaving all packages installed:"; echo "$EXTRA"; exit 1
fi
read -rp "Remove them? Packages you've since started using go too. [y/N] " a
[[ $a == [yY]* ]] || exit 0
sudo apt-get remove -y "${PKGS[@]}" && rm -f "$STATE/added-packages"

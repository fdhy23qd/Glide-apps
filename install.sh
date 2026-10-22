#!/bin/sh
# Сборка и установка приложений Glide в ~/.local (bin, applications, icons).
# Ассоциации файлов (xdg-mime default) не трогает — это отдельный шаг, см. README.
set -e
src=$(cd "$(dirname "$0")" && pwd)
prefix="${PREFIX:-$HOME/.local}"
build="$src/build"

cmake -S "$src" -B "$build" -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$prefix" >/dev/null
cmake --build "$build"
cmake --install "$build" >/dev/null

mkdir -p "$prefix/share/icons/hicolor/scalable/apps"
cp "$src"/icons/*.svg "$prefix/share/icons/hicolor/scalable/apps/"
gtk-update-icon-cache -q -t "$prefix/share/icons/hicolor" 2>/dev/null || true
update-desktop-database -q "$prefix/share/applications" 2>/dev/null || true
# откуда поставлено — Glide Shell проверяет здесь обновления приложений (git fetch)
state="${XDG_STATE_HOME:-$HOME/.local/state}/glide-shell"
mkdir -p "$state" && printf '%s\n' "$src" > "$state/apps-source"
echo "установлено:"; grep "/bin/" "$build/install_manifest.txt" | sed "s|^|  |"

#!/usr/bin/env bash
set -euo pipefail

BACKUP="$HOME/.config/center-master/decoration-backup.conf"

if [[ ! -f "$BACKUP" ]]; then
    echo "No existe una copia de la decoración anterior: $BACKUP"
    exit 1
fi

library="$(sed -n 's/^library=//p' "$BACKUP" | head -n1)"
theme="$(sed -n 's/^theme=//p' "$BACKUP" | head -n1)"

if [[ -n "$library" ]]; then
    kwriteconfig6 --file kwinrc --group org.kde.kdecoration2 --key library "$library"
else
    kwriteconfig6 --file kwinrc --group org.kde.kdecoration2 --key library org.kde.breeze
fi

if [[ -n "$theme" ]]; then
    kwriteconfig6 --file kwinrc --group org.kde.kdecoration2 --key theme "$theme"
else
    kwriteconfig6 --file kwinrc --group org.kde.kdecoration2 --delete theme
fi

if command -v qdbus6 >/dev/null 2>&1; then
    qdbus6 org.kde.KWin /KWin reconfigure
elif command -v qdbus >/dev/null 2>&1; then
    qdbus org.kde.KWin /KWin reconfigure
fi

echo "Decoración anterior restaurada."

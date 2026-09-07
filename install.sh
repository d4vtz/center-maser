#!/usr/bin/env bash
set -euo pipefail

ID="org.d4vtz.centermaster"
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

is_installed() {
    kpackagetool6 --type=KWin/Script --list 2>/dev/null | grep -Fq "$ID"
}

if is_installed; then
    kpackagetool6 --type=KWin/Script -u "$ID" || true
fi

kpackagetool6 --type=KWin/Script -i "$ROOT"
kwriteconfig6 --file kwinrc --group Plugins --key "${ID}Enabled" true

if command -v qdbus6 >/dev/null 2>&1; then
    qdbus6 org.kde.KWin /KWin reconfigure
elif command -v qdbus >/dev/null 2>&1; then
    qdbus org.kde.KWin /KWin reconfigure
else
    echo "Advertencia: no se encontró qdbus6 ni qdbus; recarga KWin manualmente."
fi

echo "Center Master instalado y habilitado."

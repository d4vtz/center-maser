#!/usr/bin/env bash
set -euo pipefail

ID="org.d4vtz.centermaster"
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
DEST="$HOME/.local/share/kwin/scripts/$ID"

# kpackagetool6 puede perder la pista del paquete aunque el directorio siga
# existiendo. En ese estado, desinstalar falla y reinstalar también. Así que
# tratamos el directorio instalado como la fuente de verdad para una
# reinstalación local.
if [[ -d "$DEST" ]]; then
    echo "Eliminando instalación anterior en $DEST"
    rm -rf -- "$DEST"
fi

# Limpiar una posible entrada registrada, pero no abortar si kpackagetool6
# considera que el complemento ya no está instalado.
kpackagetool6 --type=KWin/Script -u "$ID" >/dev/null 2>&1 || true

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

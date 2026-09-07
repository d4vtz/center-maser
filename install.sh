#!/usr/bin/env bash
set -euo pipefail

ID="org.d4vtz.centermaster"
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
DEST="$HOME/.local/share/kwin/scripts/$ID"

AURORAE_NAME="CenterMasterAccent"
AURORAE_SRC="$ROOT/aurorae/$AURORAE_NAME"
AURORAE_DEST="$HOME/.local/share/aurorae/themes/$AURORAE_NAME"
DECORATION_BACKUP_DIR="$HOME/.config/center-master"
DECORATION_BACKUP="$DECORATION_BACKUP_DIR/decoration-backup.conf"

if [[ -d "$DEST" ]]; then
    echo "Eliminando instalación anterior en $DEST"
    rm -rf -- "$DEST"
fi

kpackagetool6 --type=KWin/Script -u "$ID" >/dev/null 2>&1 || true
kpackagetool6 --type=KWin/Script -i "$ROOT"
kwriteconfig6 --file kwinrc --group Plugins --key "${ID}Enabled" true

if [[ -d "$AURORAE_SRC" ]]; then
    mkdir -p "$(dirname -- "$AURORAE_DEST")"
    rm -rf -- "$AURORAE_DEST"
    cp -a -- "$AURORAE_SRC" "$AURORAE_DEST"

    # El marco y los botones usan roles ColorScheme-* en SVG y siguen el
    # esquema de KDE. Aurorae aún espera el color del texto del título en su
    # archivo rc, así que lo sincronizamos con kdeglobals al instalar.
    title_rgb="$(kreadconfig6 --file kdeglobals --group Colors:Window --key ForegroundNormal 2>/dev/null || true)"
    if [[ "$title_rgb" =~ ^[0-9]+,[0-9]+,[0-9]+$ ]]; then
        sed -i "s/^ActiveTextColor=.*/ActiveTextColor=${title_rgb},255/"             "$AURORAE_DEST/CenterMasterAccentrc"
        sed -i "s/^InactiveTextColor=.*/InactiveTextColor=${title_rgb},170/"             "$AURORAE_DEST/CenterMasterAccentrc"
    fi

    mkdir -p "$DECORATION_BACKUP_DIR"

    if [[ ! -f "$DECORATION_BACKUP" ]]; then
        current_library="$(kreadconfig6 --file kwinrc --group org.kde.kdecoration2 --key library 2>/dev/null || true)"
        current_theme="$(kreadconfig6 --file kwinrc --group org.kde.kdecoration2 --key theme 2>/dev/null || true)"

        {
            printf 'library=%s\n' "$current_library"
            printf 'theme=%s\n' "$current_theme"
        } > "$DECORATION_BACKUP"

        echo "Decoración anterior guardada en $DECORATION_BACKUP"
    fi

    kwriteconfig6 --file kwinrc --group org.kde.kdecoration2 --key library org.kde.kwin.aurorae
    kwriteconfig6 --file kwinrc --group org.kde.kdecoration2 --key theme "__aurorae__svg__${AURORAE_NAME}"

    echo "Decoración Center Master Accent instalada y aplicada."
fi

if command -v qdbus6 >/dev/null 2>&1; then
    qdbus6 org.kde.KWin /KWin reconfigure
elif command -v qdbus >/dev/null 2>&1; then
    qdbus org.kde.KWin /KWin reconfigure
else
    echo "Advertencia: no se encontró qdbus6 ni qdbus; recarga KWin manualmente."
fi

echo "Center Master instalado y habilitado."

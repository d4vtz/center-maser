#!/usr/bin/env bash
set -euo pipefail

ID="org.d4vtz.centermaster"
ROOT="$(cd -- "$(dirname -- "$BASH_SOURCE")" && pwd)"
DEST="$HOME/.local/share/kwin/scripts/$ID"

ACCENT_NAME="CenterMasterAccent"
ACCENT_DEST="$HOME/.local/share/aurorae/themes/$ACCENT_NAME"
BACKUP_DIR="$HOME/.config/center-master"
BACKUP_FILE="$BACKUP_DIR/decoration-backup.conf"
PATCHER="$ROOT/tools/patch_aurorae.py"

read_decoration() {
    local key="$1"
    kreadconfig6 --file kwinrc --group org.kde.kdecoration2 --key "$key" 2>/dev/null || true
}

write_decoration() {
    local library="$1"
    local theme="$2"

    if [[ -n "$library" ]]; then
        kwriteconfig6 --file kwinrc --group org.kde.kdecoration2 --key library "$library"
    fi

    if [[ -n "$theme" ]]; then
        kwriteconfig6 --file kwinrc --group org.kde.kdecoration2 --key theme "$theme"
    else
        kwriteconfig6 --file kwinrc --group org.kde.kdecoration2 --delete theme
    fi
}

backup_value() {
    local key="$1"
    [[ -f "$BACKUP_FILE" ]] || return 0
    grep "^$key=" "$BACKUP_FILE" | head -n1 | cut -d= -f2-
}

find_aurorae_theme_dir() {
    local name="$1"
    local candidate

    for candidate in         "$HOME/.local/share/aurorae/themes/$name"         "/usr/share/aurorae/themes/$name"
    do
        if [[ -d "$candidate" ]]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done

    return 1
}

install_center_master_script() {
    if [[ -d "$DEST" ]]; then
        echo "Eliminando instalación anterior en $DEST"
        rm -rf -- "$DEST"
    fi

    kpackagetool6 --type=KWin/Script -u "$ID" >/dev/null 2>&1 || true
    kpackagetool6 --type=KWin/Script -i "$ROOT"
    kwriteconfig6 --file kwinrc --group Plugins --key "$ID""Enabled" true
}

install_accent_decoration() {
    mkdir -p "$BACKUP_DIR"

    local current_library current_theme
    current_library="$(read_decoration library)"
    current_theme="$(read_decoration theme)"

    local base_library="$current_library"
    local base_theme="$current_theme"

    if [[ "$current_theme" == "__aurorae__svg__$ACCENT_NAME" && -f "$BACKUP_FILE" ]]; then
        base_library="$(backup_value library)"
        base_theme="$(backup_value theme)"
        echo "Recuperando la decoración base anterior: $base_theme"
    fi

    if [[ ! -f "$BACKUP_FILE" ]]; then
        {
            printf 'library=%s\n' "$base_library"
            printf 'theme=%s\n' "$base_theme"
        } > "$BACKUP_FILE"
        echo "Decoración original guardada en $BACKUP_FILE"
    fi

    if [[ "$base_theme" != __aurorae__svg__* ]]; then
        echo "La decoración original no es Aurorae SVG."
        echo "Se conservará intacta; Center Master no sustituirá sus botones ni barra de título."
        write_decoration "$base_library" "$base_theme"
        return 0
    fi

    local base_name source_dir source_rc
    base_name="$(printf '%s' "$base_theme" | sed 's/^__aurorae__svg__//')"

    if ! source_dir="$(find_aurorae_theme_dir "$base_name")"; then
        echo "No se encontró el tema Aurorae base '$base_name'."
        echo "Restaurando la decoración original sin modificarla."
        write_decoration "$base_library" "$base_theme"
        return 0
    fi

    echo "Clonando decoración base '$base_name' para conservar su estética..."
    rm -rf -- "$ACCENT_DEST"
    mkdir -p "$(dirname -- "$ACCENT_DEST")"
    cp -a -- "$source_dir" "$ACCENT_DEST"

    source_rc="$(find "$ACCENT_DEST" -maxdepth 1 -type f -name '*rc' -print -quit)"

    if [[ -z "$source_rc" ]]; then
        echo "El tema base no contiene archivo rc; restaurando decoración original."
        rm -rf -- "$ACCENT_DEST"
        write_decoration "$base_library" "$base_theme"
        return 0
    fi

    if [[ "$source_rc" != "$ACCENT_DEST/$ACCENT_NAME""rc" ]]; then
        mv -- "$source_rc" "$ACCENT_DEST/$ACCENT_NAME""rc"
    fi

    if [[ ! -f "$ACCENT_DEST/decoration.svg" ]]; then
        echo "El tema base no contiene decoration.svg; restaurando decoración original."
        rm -rf -- "$ACCENT_DEST"
        write_decoration "$base_library" "$base_theme"
        return 0
    fi

    python3 "$PATCHER" "$ACCENT_DEST/decoration.svg"

    if [[ -f "$ACCENT_DEST/metadata.desktop" ]]; then
        if grep -q '^Name=' "$ACCENT_DEST/metadata.desktop"; then
            sed -i 's/^Name=.*/Name=Center Master Accent/' "$ACCENT_DEST/metadata.desktop"
        else
            printf '\nName=Center Master Accent\n' >> "$ACCENT_DEST/metadata.desktop"
        fi
    fi

    kwriteconfig6 --file kwinrc --group org.kde.kdecoration2 --key library org.kde.kwin.aurorae
    kwriteconfig6 --file kwinrc --group org.kde.kdecoration2 --key theme "__aurorae__svg__$ACCENT_NAME"

    echo "Borde agregado sobre '$base_name' conservando botones, barra de título y sombras."
}

install_center_master_script
install_accent_decoration

if command -v qdbus6 >/dev/null 2>&1; then
    qdbus6 org.kde.KWin /KWin reconfigure
elif command -v qdbus >/dev/null 2>&1; then
    qdbus org.kde.KWin /KWin reconfigure
else
    echo "Advertencia: no se encontró qdbus6 ni qdbus; recarga KWin manualmente."
fi

echo "Center Master instalado y habilitado."

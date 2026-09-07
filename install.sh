#!/usr/bin/env bash
set -euo pipefail

ID="org.d4vtz.centermaster"
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

if kpackagetool6 --type=KWin/Script --list | grep -q "$ID"; then
    kpackagetool6 --type=KWin/Script -u "$ID"
fi

kpackagetool6 --type=KWin/Script -i "$ROOT"
kwriteconfig6 --file kwinrc --group Plugins --key "${ID}Enabled" true
qdbus6 org.kde.KWin /KWin reconfigure

echo "Center Master installed and enabled."

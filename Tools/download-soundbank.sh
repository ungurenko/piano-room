#!/bin/bash
# Скачивает рояль Salamander Grand Piano (SF2) в Resources/SoundBanks.
set -euo pipefail
cd "$(dirname "$0")/.."

DEST="Resources/SoundBanks"
FILE="$DEST/Salamander.sf2"
URL="https://freepats.zenvoid.org/Piano/SalamanderGrandPiano/SalamanderGrandPiano-SF2-V3+20200602.tar.xz"
TMP="/tmp/pianoroom-soundbank"

if [ -f "$FILE" ]; then
  echo "Рояль уже на месте: $FILE"
  exit 0
fi

mkdir -p "$DEST" "$TMP"
echo "Скачиваем Salamander Grand Piano (архив ~296 МБ)…"
curl -L --fail --progress-bar -o "$TMP/salamander.tar.xz" "$URL"

echo "Распаковываем…"
tar -xJf "$TMP/salamander.tar.xz" -C "$TMP"

FOUND=$(find "$TMP" -name "SalamanderGrandPiano*.sf2" -print -quit)
if [ -z "$FOUND" ]; then
  echo "Не удалось найти .sf2 в архиве."
  exit 1
fi

mv "$FOUND" "$FILE"
rm -rf "$TMP"
echo "Готово: $FILE"

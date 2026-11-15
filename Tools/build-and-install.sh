#!/bin/bash
# Собирает Piano Room и устанавливает в /Applications.
set -euo pipefail
cd "$(dirname "$0")/.."

bash Tools/download-pianos.sh

echo "1/4 Генерируем проект…"
xcodegen generate > /dev/null

echo "2/4 Собираем…"
xcodebuild -project PianoRoom.xcodeproj -scheme PianoRoom -configuration Release \
  -derivedDataPath build build > /tmp/pianoroom-build.log 2>&1

APP="build/Build/Products/Release/Piano Room.app"
if [ ! -d "$APP" ]; then
  echo "Сборка не удалась. Смотри /tmp/pianoroom-build.log"
  exit 1
fi

echo "3/4 Устанавливаем в /Applications…"
pkill -f "Piano Room.app" 2>/dev/null || true
sleep 1
ditto "$APP" "/Applications/Piano Room.app"
# LaunchServices иногда не успевает узнать перезаписанный бандл.
sleep 1

echo "4/4 Запускаем…"
if ! open "/Applications/Piano Room.app" 2>/dev/null; then
  sleep 2
  open "/Applications/Piano Room.app"
fi

sleep 3
if pgrep -f "/Applications/Piano Room.app" > /dev/null; then
  echo "Готово: приложение запущено."
else
  echo "Скопировано, но запустить не удалось. Открой «Программы» → Piano Room вручную."
fi

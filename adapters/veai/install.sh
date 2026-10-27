#!/bin/sh
# Установка veai-адаптера плагина sae-claude-plugin.
# Ставит расширение в ~/.veai/extensions/ как симлинк на этот каталог.
# Повторный запуск обновляет симлинк (тот же источник — ничего не делает).

set -eu

REPO_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
SRC="$REPO_ROOT/adapters/veai/sae-task"
DEST_DIR="${HOME}/.veai/extensions"
DEST="$DEST_DIR/sae-task"

[ -f "$SRC/index.ts" ] || { echo "нет $SRC/index.ts" >&2; exit 1; }

mkdir -p "$DEST_DIR"

# .bak от предыдущей правки не трогаем.
if [ -e "$DEST" ] || [ -L "$DEST" ]; then
  CURRENT=$(readlink "$DEST" 2>/dev/null || true)
  if [ "$CURRENT" = "$SRC" ]; then
    echo "уже установлено: $DEST -> $SRC"
    exit 0
  fi
  rm -rf "$DEST"
fi

ln -s "$SRC" "$DEST"
echo "установлено: $DEST -> $SRC"
echo "проверь: veai extensions check"

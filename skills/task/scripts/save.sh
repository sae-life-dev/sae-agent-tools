#!/bin/sh
# save.sh <файл> <папка> <имя> [<размер>] — кладёт файл, который Claude Code сохранил из ответа
# MCP (tool-results/…), в папку материалов задачи под настоящим именем вложения. Папка
# создаётся; она должна лежать внутри «…/материалы/». Имя занято другим файлом — _2, _3…;
# тот же файл — SAME. Размер — из списка вложений: не совпал — SIZE_MISMATCH.
# Первая строка вывода — итог: SAVED, SAME, NO_FILE, NOT_MATERIALS, NO_ARG или код сбоя;
# следом size=<байт>, при несовпадении — SIZE_MISMATCH expected=… got=…. Исходник не трогает.
set -u
. "$(dirname "$0")/lib.sh"

if [ $# -lt 3 ] || [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ]; then
  say "NO_ARG"
  exit 2
fi
if [ ! -f "$1" ]; then
  say "NO_FILE $1"
  exit 3
fi
abs_path "$2"
case $abs_path/ in
  */материалы/*) ;;
  *)
    say "NOT_MATERIALS $abs_path"
    exit 3
    ;;
esac

place_file "$1" "$abs_path" "$3" "${4:-}" || exit 6

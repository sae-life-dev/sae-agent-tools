#!/bin/sh
# recent.sh — три задачи с наибольшими номерами в папке задач из настроек проекта
# (.claude/sae.local.md, ключ task.dir). Служебные папки «_…» (архив) не смотрит. Ничего не меняет.
# Первая строка вывода — итог: RECENT, EMPTY, BAD_ARG или код из настроек (NO_CONFIG,
# CONFIG_NO_KEY, TASKS_MISSING, TASKS_UNMARKED). После RECENT — по две строки на задачу, от
# большего номера: «task=<номер как в имени папки> <папка>» и «title=<название>».
set -u
. "$(dirname "$0")/lib.sh"

if [ $# -gt 0 ]; then
  say "BAD_ARG $1"
  exit 2
fi
tasks_root_from_config || exit 3

us=$(printf '\037')

list=$(for d in "$tasks_root"/[0-9]*_*; do
  [ -d "$d" ] || continue
  entry_number "$d"
  [ -n "$entry_number" ] || continue
  b=${d##*/}
  printf '%s\n' "$entry_number$us${b%%_*}$us$d"
done | sort -t "$us" -k1,1nr -k3,3 | head -n 3)

if [ -z "$list" ]; then
  say "EMPTY $tasks_root"
  exit 0
fi

say "RECENT $tasks_root"
while IFS=$us read -r n number dir; do
  task_title "$dir"
  title=$task_title
  # Нет заголовка — имя папки без номера: номер стоит в строке task=.
  [ "$title" = "${dir##*/}" ] && title=${title#*_}
  say "task=$number $dir"
  say "title=$title"
done <<EOF
$list
EOF

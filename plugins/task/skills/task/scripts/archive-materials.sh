#!/bin/sh
# archive-materials.sh <папка задачи> — убирает прошлую выгрузку из Jira и КБ (материалы/jira/,
# материалы/кб/, материалы/индекс.md) в материалы/_прошлое_<ГГГГ-ММ-ДД>/, чтобы выгрузить
# заново. Имя занято — _2, _3 и т. д. Остальное в материалы/ (старые анализы) не трогает.
# Первая строка вывода — итог: MOVED, NO_MATERIALS, NO_DIR, NOT_TASK, NO_ARG или код сбоя;
# при сбое следом — текст системной ошибки. После MOVED — строка to=<куда>.
set -u
. "$(dirname "$0")/lib.sh"

if [ $# -lt 1 ] || [ -z "$1" ]; then
  say "NO_ARG"
  exit 2
fi

abs_path "$1"
if [ ! -d "$abs_path" ]; then
  say "NO_DIR $abs_path"
  exit 3
fi
physical "$abs_path" || exit 3
task=$physical_path
if [ ! -f "$task/задача.md" ]; then
  say "NOT_TASK $task"
  exit 3
fi

mat=$task/материалы
found=
for p in jira кб индекс.md; do
  [ -e "$mat/$p" ] && found="$found $p"
done
if [ -z "$found" ]; then
  say "NO_MATERIALS $mat"
  exit 3
fi

stem=$mat/_прошлое_$(date +%Y-%m-%d)
dest=$stem
n=1
while [ -e "$dest" ] || [ -L "$dest" ]; do
  n=$((n + 1))
  dest=${stem}_$n
done
if ! err=$(mkdir "$dest" 2>&1); then
  say "MKDIR_FAILED $dest"
  say "$err"
  exit 6
fi
for p in $found; do
  if ! err=$(mv "$mat/$p" "$dest/$p" 2>&1); then
    say "MOVE_FAILED $mat/$p"
    say "$err"
    exit 6
  fi
done
say "MOVED $mat"
say "to=$dest"

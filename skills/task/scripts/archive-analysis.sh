#!/bin/sh
# archive-analysis.sh <папка задачи> — убирает анализ.md в материалы/анализ_<ГГГГ-ММ-ДД>.md,
# чтобы написать анализ заново. Имя занято — добавляется _2, _3 и т. д. Папку материалы/
# создаёт, если её нет. Ничего другого не трогает.
# Первая строка вывода — итог: MOVED, NO_ANALYSIS, NO_DIR, NOT_TASK, NO_ARG или код сбоя;
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
if [ ! -f "$task/анализ.md" ]; then
  say "NO_ANALYSIS $task"
  exit 3
fi

dest_dir=$task/материалы
if [ -e "$dest_dir" ] && [ ! -d "$dest_dir" ]; then
  say "NOT_DIR $dest_dir"
  exit 3
fi
if [ ! -d "$dest_dir" ] && ! err=$(mkdir "$dest_dir" 2>&1); then
  say "MKDIR_FAILED $dest_dir"
  say "$err"
  exit 6
fi

stem=$dest_dir/анализ_$(date +%Y-%m-%d)
dest=$stem.md
n=1
while [ -e "$dest" ] || [ -L "$dest" ]; do
  n=$((n + 1))
  dest=${stem}_$n.md
done

if ! err=$(mv "$task/анализ.md" "$dest" 2>&1); then
  say "MOVE_FAILED $task/анализ.md"
  say "$err"
  exit 6
fi
say "MOVED $task/анализ.md"
say "to=$dest"

#!/bin/sh
# close.sh [--open-ok] <папка задачи> — закрывает задачу: переносит папку в _архив/ папки задач
# с тем же именем (номер не меняется). _архив/ создаётся при первом закрытии. Папка задачи
# должна лежать прямо в папке задач (README.md с шапкой «sae: tasks»).
# Есть незакрытые подзадачи (подзадачи/NN_<имя>.md с шапкой «sae: subtask» без «status: done») —
# стоп; --open-ok — закрыть всё равно, по явному «да» владельца.
# Первая строка вывода — итог: ARCHIVED, SUBTASKS_OPEN, ALREADY_ARCHIVED, NOT_IN_TASKS, EXISTS,
# NO_DIR, NOT_DIR, NOT_TASK, NO_ARG, BAD_ARG или код сбоя; при сбое следом — текст системной
# ошибки. После ARCHIVED — to=<куда>; после SUBTASKS_OPEN — open=<имя файла> на каждую.
set -u
. "$(dirname "$0")/lib.sh"

open_ok=no
if [ "${1-}" = --open-ok ]; then
  open_ok=yes
  shift
fi
if [ $# -lt 1 ] || [ -z "$1" ]; then
  say "NO_ARG"
  exit 2
fi
if [ $# -gt 1 ]; then
  say "BAD_ARG $2"
  exit 2
fi
abs_path "$1"
if [ ! -e "$abs_path" ]; then
  say "NO_DIR $abs_path"
  exit 3
fi
if [ ! -d "$abs_path" ]; then
  say "NOT_DIR $abs_path"
  exit 3
fi
physical "$abs_path" || exit 3
task=$physical_path
if [ ! -f "$task/задача.md" ]; then
  say "NOT_TASK $task"
  exit 3
fi
parent=$(dirname "$task")
case ${parent##*/} in
  _*)
    say "ALREADY_ARCHIVED $task"
    exit 4
    ;;
esac
if ! is_tasks_root "$parent"; then
  say "NOT_IN_TASKS $task"
  exit 4
fi

sub=$task/подзадачи
open=
if [ -d "$sub" ]; then
  for f in "$sub"/*; do
    [ -f "$f" ] || continue
    b=${f##*/}
    case $b in
      *_*.md) ;;
      *) continue ;;
    esac
    entry_number "$b"
    [ -n "$entry_number" ] || continue
    [ "$(config_value "$f" sae)" = subtask ] || continue
    [ "$(config_value "$f" status)" = done ] && continue
    open="${open}open=$b
"
  done
fi
if [ -n "$open" ] && [ "$open_ok" = no ]; then
  say "SUBTASKS_OPEN $task"
  printf '%s' "$open"
  exit 4
fi

archive=$parent/_архив
dest=$archive/${task##*/}
if [ -e "$archive" ] && [ ! -d "$archive" ]; then
  say "NOT_DIR $archive"
  exit 3
fi
if [ -e "$dest" ] || [ -L "$dest" ]; then
  say "EXISTS $dest"
  exit 4
fi
if [ ! -d "$archive" ] && ! err=$(mkdir "$archive" 2>&1); then
  say "MKDIR_FAILED $archive"
  say "$err"
  exit 6
fi
if ! err=$(mv "$task" "$dest" 2>&1); then
  say "MOVE_FAILED $task"
  say "$err"
  exit 6
fi
say "ARCHIVED $task"
say "to=$dest"

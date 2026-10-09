#!/bin/sh
# locate.sh <путь или номер> — находит задачу и сообщает её состояние.
# Только цифры — номер: ищется среди записей «NNN_…» в папке задач из настроек проекта
# (.claude/sae.local.md, ключ task.dir) и в служебных папках «_…» (архив); 24 и 024 — один номер.
# Иначе — путь к папке задачи (в ней лежит задача.md), настройки не нужны.
# Первая строка вывода — итог: FOUND, NOT_FOUND, AMBIGUOUS, NO_DIR, NOT_DIR, NOT_TASK, NO_ARG
# или код из настроек (NO_CONFIG, CONFIG_NO_KEY, TASKS_MISSING, TASKS_UNMARKED). После FOUND —
# task=empty|filled|missing (в задача.md нет ничего, кроме заголовков, комментариев и строки
# «**Jira:** …», — empty; файла нет — missing),
# analysis=none|exists, archived=yes|no. Ничего не меняет.
set -u
. "$(dirname "$0")/lib.sh"

if [ $# -lt 1 ] || [ -z "$1" ]; then
  say "NO_ARG"
  exit 2
fi

case $1 in
  *[!0-9]*)
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
    ;;
  *)
    tasks_root_from_config || exit 3
    wanted=$(expr "$1" + 0)
    found=0
    task=
    list=
    for d in "$tasks_root"/[0-9]*_* "$tasks_root"/_*/[0-9]*_*; do
      [ -d "$d" ] || continue
      entry_number "$d"
      [ "$entry_number" = "$wanted" ] || continue
      found=$((found + 1))
      task=$d
      list="$list$d
"
    done
    if [ "$found" -eq 0 ]; then
      say "NOT_FOUND $1"
      say "tasks.root=$tasks_root"
      exit 3
    fi
    if [ "$found" -gt 1 ]; then
      say "AMBIGUOUS $1"
      printf '%s' "$list"
      exit 4
    fi
    ;;
esac

if [ ! -f "$task/задача.md" ]; then
  state=missing
elif awk '
  { sub(/\r$/, "") }
  {
    line = $0
    out = ""
    while (line != "") {
      if (incomment) {
        i = index(line, "-->")
        if (i == 0) { line = ""; break }
        line = substr(line, i + 3)
        incomment = 0
      } else {
        i = index(line, "<!--")
        if (i == 0) { out = out line; line = "" }
        else { out = out substr(line, 1, i - 1); line = substr(line, i + 4); incomment = 1 }
      }
    }
    if (out ~ /^[ \t]*#/) next
    if (out ~ /^[ \t]*\*\*Jira:\*\*/) next
    if (out ~ /[^ \t]/) { filled = 1; exit }
  }
  END { exit !filled }
' "$task/задача.md"; then
  state=filled
else
  state=empty
fi
if [ -f "$task/анализ.md" ]; then
  analysis=exists
else
  analysis=none
fi
parent=$(dirname "$task")
case ${parent##*/} in
  _*) archived=yes ;;
  *) archived=no ;;
esac

say "FOUND $task"
say "task=$state"
say "analysis=$analysis"
say "archived=$archived"

#!/bin/sh
# locate.sh <путь или номер> — находит задачу и сообщает её состояние.
# Только цифры — номер: ищется среди записей «NNN_…» в папке задач из настроек проекта
# (.claude/sae.local.md, ключ task.dir) и в служебных папках «_…» (архив); 24 и 024 — один номер.
# Иначе — путь к папке задачи (в ней лежит задача.md), настройки не нужны.
# Первая строка вывода — итог: FOUND, NOT_FOUND, AMBIGUOUS, NO_DIR, NOT_DIR, NOT_TASK, NO_ARG
# или код из настроек (NO_CONFIG, CONFIG_NO_KEY, TASKS_MISSING, TASKS_UNMARKED). После FOUND —
# task=empty|filled|missing (в задача.md нет ничего, кроме заголовков, комментариев и строки
# «**Jira:** …», — empty; файла нет — missing),
# analysis=none|exists (анализ.md нет или в нём одни пробелы — none), archived=yes|no,
# jira=<КЛЮЧ>|none (строка «**Jira:** …» в задача.md), materials=none|partial|done
# (материалы/индекс.md нет — none; иначе status из его шапки, не done — partial),
# done_criteria=empty — только при task=filled, если раздел «Как пойму, что готово» пуст или его нет.
# Ничего не меняет.
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

done_criteria=
if [ ! -f "$task/задача.md" ]; then
  state=missing
else
  # Два слова: заполнена ли задача и раздел «Как пойму, что готово» (до следующего # или ##).
  scan=$(awk '
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
      if (out ~ /^[ \t]*##?[ \t]/) indone = (out ~ /^[ \t]*##?[ \t]+Как пойму, что готово[ \t]*$/)
      if (out ~ /^[ \t]*#/) next
      if (out ~ /^[ \t]*\*\*Jira:\*\*/) next
      if (out ~ /[^ \t]/) { filled = 1; if (indone) done = 1 }
    }
    END { print (filled ? "filled" : "empty"), (done ? "filled" : "empty") }
  ' "$task/задача.md")
  state=${scan% *}
  done_criteria=${scan#* }
fi
if [ -f "$task/анализ.md" ] && grep -q '[^[:space:]]' "$task/анализ.md"; then
  analysis=exists
else
  analysis=none
fi
jira=
if [ -f "$task/задача.md" ]; then
  jira=$(awk '
    { sub(/\r$/, ""); gsub(/^[ \t]+|[ \t]+$/, "") }
    index($0, "**Jira:**") == 1 { v = substr($0, 10); gsub(/^[ \t]+/, "", v); print v; exit }
  ' "$task/задача.md")
# Прочерк в строке «**Jira:** —» — «ключа нет», как и пустая строка.
case $jira in
  ''|[-–—]) jira=none ;;
esac
fi
[ -n "$jira" ] || jira=none
if [ ! -f "$task/материалы/индекс.md" ]; then
  materials=none
elif [ "$(config_value "$task/материалы/индекс.md" status)" = done ]; then
  materials=done
else
  materials=partial
fi
parent=$(dirname "$task")
case ${parent##*/} in
  _*) archived=yes ;;
  *) archived=no ;;
esac

say "FOUND $task"
say "task=$state"
if [ "$state" = filled ] && [ "$done_criteria" = empty ]; then
  say "done_criteria=empty"
fi
say "analysis=$analysis"
say "archived=$archived"
say "jira=$jira"
say "materials=$materials"
if [ "$state" = empty ] && [ "$jira" != none ] && [ "$archived" = no ]; then
  say "hint=задача.md пустой, ключ Jira есть: заполни по steps/fill-task.md (next и analyze ведут туда сами)"
fi

#!/bin/sh
# progress.sh <папка задачи> — состояние подзадач и какую брать дальше. Ничего не меняет.
# Смотрит файлы подзадачи/NN_<имя>.md с шапкой «sae: subtask»; файлы без шапки и прочие
# не считает (о них сообщает split.sh). «Зависит от» — из source: в шапке файла.
# Первая строка вывода — итог: PROGRESS, NO_SUBTASKS, NO_DIR, NOT_DIR, NOT_TASK, NO_ARG,
# BAD_ARG. После PROGRESS — строка на файл, по номерам:
# «П<N> <состояние> steps=K/M checks=a/b deps=П1,П2|— blocked=yes|no file=<имя>», состояния:
# open, done, draft (остались метки «<!-- заполнить»), nosteps (в разделе 2 нет шагов),
# badsteps (шаги не «- [ ] N. …» с 1 подряд; line=<строка файла> перед file=), dup (у номера
# несколько файлов). blocked=yes — не все «Зависит от» закрыты (status: done).
# Последняя строка — что дальше: «next=П<N> step=K» (первая по номеру open с закрытыми
# зависимостями, K — её первый неотмеченный шаг), «next=П<N> close» (у неё все шаги отмечены),
# «next=none» (открытые есть, взять нечего: заблокированы или не готовы), «all=done».
set -u
. "$(dirname "$0")/lib.sh"

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
sub=$task/подзадачи
if [ -e "$sub" ] && [ ! -d "$sub" ]; then
  say "NOT_DIR $sub"
  exit 3
fi

us=$(printf '\037')

# Строки «номер \037 состояние \037 поля \037 зависимости \037 имя» по каждому файлу.
rows=
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
    subtask_read "$f"
    if [ "$sub_status" = done ]; then
      state=done
    elif [ "$sub_draft" = yes ]; then
      state=draft
    elif [ -n "$steps_bad" ]; then
      state=badsteps
    elif [ "$steps_total" -eq 0 ]; then
      state=nosteps
    else
      state=open
    fi
    # Номера П из ячейки «Зависит от» строки source: (четвёртая, «\|» — не граница).
    deps=$(config_value "$f" source | awk '
      {
        gsub(/\\\|/, "\001")
        if (split($0, c, "|") < 4) exit
        s = c[4]
        out = ""
        while (match(s, /П[0-9]+/)) {
          r = substr(s, RSTART, RLENGTH)
          s = substr(s, RSTART + RLENGTH)
          sub(/^П/, "", r)
          r = r + 0
          if (!(r in seen)) { seen[r] = 1; out = out (out == "" ? "" : ",") "П" r }
        }
        print out
      }
    ')
    fields="steps=$steps_done/$steps_total checks=$checks_done/$checks_total"
    rows="$rows$entry_number$us$state$us$fields$us$deps$us$step_first$us$steps_bad$us$b
"
  done
fi

if [ -z "$rows" ]; then
  say "NO_SUBTASKS $task"
  exit 0
fi

say "PROGRESS $task"
printf '%s' "$rows" | sort -t "$us" -k1,1n -k7,7 | awk -F "$us" '
  { n[NR] = $1; st[NR] = $2; fl[NR] = $3; dp[NR] = $4; first[NR] = $5; bad[NR] = $6; nm[NR] = $7
    count[$1]++ }
  END {
    for (i = 1; i <= NR; i++) {
      if (count[n[i]] > 1) st[i] = "dup"
      if (count[n[i]] == 1 && st[i] == "done") closed[n[i]] = 1
    }
    pick = ""
    open = 0
    for (i = 1; i <= NR; i++) {
      blocked = "no"
      m = split(dp[i], d, ",")
      for (j = 1; j <= m; j++) {
        r = d[j]
        sub(/^П/, "", r)
        if (!((r + 0) in closed)) blocked = "yes"
      }
      if (st[i] != "done") open++
      if (pick == "" && st[i] == "open" && blocked == "no")
        pick = (first[i] == "") ? "next=П" n[i] " close" : "next=П" n[i] " step=" first[i]
      line = "П" n[i] " " st[i] " " fl[i] " deps=" (dp[i] == "" ? "—" : dp[i]) " blocked=" blocked
      if (st[i] == "badsteps") line = line " line=" bad[i]
      print line " file=" nm[i]
    }
    if (pick != "") print pick
    else if (open > 0) print "next=none"
    else print "all=done"
  }
'

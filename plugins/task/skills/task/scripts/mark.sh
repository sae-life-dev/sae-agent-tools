#!/bin/sh
# mark.sh step <файл подзадачи> <K> — отмечает шаг K («- [ ] K.» → «- [x] K.» в разделе 2);
# только первый неотмеченный: шаги идут по порядку.
# mark.sh done <файл подзадачи> [<номер признака> …] — закрывает подзадачу: отмечает названные
# признаки раздела 3 (номер — по порядку в разделе, с 1; остальные не трогает) и пишет
# «status: done» в шапку. Только когда все шаги отмечены.
# Разбор файла — subtask_read из lib.sh. Файл переписывается целиком через временный рядом.
# Первая строка вывода — итог: MARKED, CLOSED, NO_ARG, BAD_ARG, DUP_ARG, NO_FILE, NOT_FILE,
# NOT_SUBTASK, ALREADY_DONE, DRAFT, BAD_STEPS, NO_STEPS, NO_STEP, ALREADY, NOT_NEXT,
# STEPS_OPEN, NO_CHECK или код сбоя; при сбое следом — текст системной ошибки.
# После MARKED — step=K и steps=<отмечено>/<всего>; после CLOSED — checks=<отмечено>/<всего>.
# NOT_NEXT — first=<первый неотмеченный>, STEPS_OPEN — first=…, BAD_STEPS — line=<строка>.
set -u
. "$(dirname "$0")/lib.sh"

if [ $# -lt 2 ] || [ -z "$2" ]; then
  say "NO_ARG"
  exit 2
fi
mode=$1
case $mode in
  step | done) ;;
  *)
    say "BAD_ARG $mode"
    exit 2
    ;;
esac
abs_path "$2"
shift 2
if [ ! -e "$abs_path" ] && [ ! -L "$abs_path" ]; then
  say "NO_FILE $abs_path"
  exit 3
fi
if [ ! -f "$abs_path" ] || [ -L "$abs_path" ]; then
  say "NOT_FILE $abs_path"
  exit 3
fi
physical "$(dirname "$abs_path")" || exit 3
file=$physical_path/${abs_path##*/}
if ! config_well_formed "$file" || [ "$(config_value "$file" sae)" != subtask ]; then
  say "NOT_SUBTASK $file"
  exit 4
fi

subtask_read "$file"
if [ "$sub_status" = done ]; then
  say "ALREADY_DONE $file"
  exit 4
fi
if [ "$sub_draft" = yes ]; then
  say "DRAFT $file"
  exit 4
fi
if [ -n "$steps_bad" ]; then
  say "BAD_STEPS $file"
  say "line=$steps_bad"
  exit 4
fi
if [ "$steps_total" -eq 0 ]; then
  say "NO_STEPS $file"
  exit 4
fi

us=$(printf '\037')

is_number() {
  case $1 in
    '' | *[!0-9]*) return 1 ;;
  esac
}

# Строка файла по виду (S | C) и номеру; номер шага — свой, признака — по порядку.
line_of() {
  printf '%s\n' "$sub_scan" | awk -F "$us" -v k="$1" -v n="$2" '$1 == k && $3 == n { print $2; exit }'
}

if [ "$mode" = step ]; then
  if [ $# -ne 1 ]; then
    if [ $# -eq 0 ]; then
      say "NO_ARG"
    else
      say "BAD_ARG $2"
    fi
    exit 2
  fi
  if ! is_number "$1"; then
    say "BAD_ARG $1"
    exit 2
  fi
  k=$(expr "$1" + 0)
  if [ "$k" -lt 1 ] || [ "$k" -gt "$steps_total" ]; then
    say "NO_STEP $k"
    say "steps=$steps_total"
    exit 4
  fi
  state=$(printf '%s\n' "$sub_scan" | awk -F "$us" -v n="$k" '$1 == "S" && $3 == n { print $4; exit }')
  if [ "$state" = x ]; then
    say "ALREADY $k"
    exit 4
  fi
  if [ "$step_first" != "$k" ]; then
    say "NOT_NEXT $k"
    say "first=$step_first"
    exit 4
  fi
  lines=$(line_of S "$k")
else
  if [ -n "$step_first" ]; then
    say "STEPS_OPEN $file"
    say "first=$step_first"
    exit 4
  fi
  lines=
  given=
  for arg in "$@"; do
    if ! is_number "$arg"; then
      say "BAD_ARG $arg"
      exit 2
    fi
    c=$(expr "$arg" + 0)
    case " $given " in
      *" $c "*)
        say "DUP_ARG $c"
        exit 2
        ;;
    esac
    if [ "$c" -lt 1 ] || [ "$c" -gt "$checks_total" ]; then
      say "NO_CHECK $c"
      say "checks=$checks_total"
      exit 4
    fi
    given="$given $c"
    lines="$lines $(line_of C "$c")"
  done
fi

tmp=$file.sae-tmp.$$
if ! err=$(LINES=" $lines " MODE=$mode awk '
  BEGIN { split(ENVIRON["LINES"], l, " "); for (i in l) mark[l[i]] = 1 }
  {
    cr = ""
    line = $0
    if (sub(/\r$/, "", line)) cr = "\r"
    if (NR in mark) { sub(/^- \[ \]/, "- [x]", line); print line cr; next }
    if (ENVIRON["MODE"] == "done") {
      if (NR == 1 && line == "---") { head = 1; print; next }
      if (head && line ~ /^status:/) { print "status: done" cr; seen = 1; next }
      if (head && line == "---") {
        if (!seen) print "status: done" cr
        head = 0
      }
    }
    print
  }
' "$file" 2>&1 >"$tmp") || ! err=$(mv "$tmp" "$file" 2>&1); then
  rm -f "$tmp"
  say "WRITE_FAILED $file"
  say "$err"
  exit 6
fi

subtask_read "$file"
if [ "$mode" = step ]; then
  say "MARKED $file"
  say "step=$k"
  say "steps=$steps_done/$steps_total"
else
  say "CLOSED $file"
  say "checks=$checks_done/$checks_total"
fi

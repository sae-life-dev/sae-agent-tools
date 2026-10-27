#!/bin/sh
# split.sh <папка задачи> — сверяет раздел 7 анализа с файлами подзадачи/ и ничего не меняет.
# split.sh --create <папка задачи> <N>=<имя> … — создаёт заготовки подзадачи/<NN>_<имя>.md из
# templates/subtask.md для всех строк «new»: шапка (sae: subtask, source: <строка раздела 7>),
# заголовок, паспорт, ссылки «Зависит от»; остальное дописывает Claude по меткам «<!-- заполнить».
# Строка раздела 7: | П<N> | Подзадача | Где | Зависит от | Размер |; файл NN = П-номер (01 ↔ П1).
# Сначала проверяются открытые вопросы раздела 6 («> ❓ **В…**»): есть — стоп.
# Первая строка вывода — итог: PLAN, CREATED, QUESTIONS_OPEN, NO_SPLIT, NO_TABLE, BAD_TABLE,
# BAD_ANALYSIS, NO_ANALYSIS, NO_DIR, NOT_DIR, NOT_TASK, NO_ARG, BAD_ARG, NO_ROW, DUP_ARG, NOT_NEW,
# MISSING, BAD_NAME, EXISTS, NO_TEMPLATE или код сбоя; при сбое следом — текст системной ошибки.
# После PLAN — строка на каждую строку раздела 7: «П<N> new <подзадача>», «П<N> ok|draft|foreign
# <файл>» (готов | не дописан — остались метки | без шапки sae: subtask), «П<N> changed <файл>»
# со строками was=, now=, unfilled=yes|no, «П<N> dup <файл>» на каждый файл с тем же номером;
# затем «gone <файл>» (номера нет в разделе 7), «extra <имя>» (не NN_<имя>.md), dep.missing=П<N> П<M>.
# После CREATED — file=<путь> на каждую заготовку.
set -u
. "$(dirname "$0")/lib.sh"

us=$(printf '\037')

mode=plan
if [ "${1-}" = --create ]; then
  mode=create
  shift
fi
if [ $# -lt 1 ] || [ -z "$1" ]; then
  say "NO_ARG"
  exit 2
fi
abs_path "$1"
shift
if [ "$mode" = plan ] && [ $# -gt 0 ]; then
  say "BAD_ARG $1"
  exit 2
fi
if [ "$mode" = create ] && [ $# -eq 0 ]; then
  say "NO_ARG"
  exit 2
fi
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
analysis=$task/анализ.md
if [ ! -f "$analysis" ]; then
  say "NO_ANALYSIS $task"
  exit 3
fi
sub=$task/подзадачи
if [ -e "$sub" ] && [ ! -d "$sub" ]; then
  say "NOT_DIR $sub"
  exit 3
fi

# Разбор анализа. Строки вывода, поля через \037: S6/S7 — раздел найден; Q <вопрос>;
# NONE <текст> — «нет: …» в разделе 7; R <номер> <подзадача> <где> <зависит> <размер>;
# E <строка> <что не так>; W <номер> <ссылка> — «Зависит от» ссылается на несуществующую П.
# Блоки ``` и ~~~ пропускаются. Раздел кончается на «## », «---» или «<details».
parsed=$(awk '
  function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
  function cells(line,    n, i, c) {
    gsub(/\\\|/, "\001", line)
    line = trim(line)
    sub(/^\|/, "", line)
    sub(/\|$/, "", line)
    n = split(line, c, "|")
    for (i = 1; i <= n; i++) {
      c[i] = trim(c[i])
      gsub(/\001/, "\\|", c[i])
      gsub(/\t/, " ", c[i])
      cell[i] = c[i]
    }
    return n
  }
  BEGIN { US = "\037" }
  { sub(/\r$/, "") }
  /^[ \t]*(```|~~~)/ { fence = !fence; next }
  fence { next }
  /^## / {
    sec = ""
    if ($0 ~ /^## 6\./) { sec = 6; print "S6" }
    else if ($0 ~ /^## 7\./) { sec = 7; print "S7" }
    next
  }
  sec != "" && (/^---[ \t]*$/ || /^<details/) { sec = ""; next }
  sec == 6 && index($0, "> ❓") == 1 {
    q = $0
    i = index(q, "**")
    if (i > 0) {
      q = substr(q, i + 2)
      j = index(q, "**")
      if (j > 0) q = substr(q, 1, j - 1)
    }
    print "Q" US trim(q)
    next
  }
  sec != 7 { next }
  /^[ \t]*\|/ {
    if (tdone) next
    t++
    n = cells($0)
    if (t == 1) {
      if (n != 5 || cell[1] != "№" || cell[2] != "Подзадача" || cell[3] != "Где" ||
          cell[4] != "Зависит от" || cell[5] != "Размер")
        print "E" US NR US "header"
      next
    }
    if (t == 2) {
      if ($0 !~ /^[ \t]*\|[ \t:|-]+$/) print "E" US NR US "separator"
      next
    }
    if (n != 5) { print "E" US NR US "cells=" n; next }
    num = cell[1]
    if (num !~ /^П[0-9]+$/) { print "E" US NR US "number " num; next }
    sub(/^П/, "", num)
    num = num + 0
    if (num in seen) { print "E" US NR US "dup П" num; next }
    if (cell[2] == "") { print "E" US NR US "title П" num; next }
    seen[num] = 1
    for (i = 3; i <= 5; i++) if (cell[i] == "") cell[i] = "—"
    deps[num] = cell[4]
    order[++rows] = num
    print "R" US num US cell[2] US cell[3] US cell[4] US cell[5]
    next
  }
  t > 0 { tdone = 1 }
  t == 0 && /^(Нет|нет):/ { print "NONE" US trim($0) }
  END {
    for (k = 1; k <= rows; k++) {
      s = deps[order[k]]
      while (match(s, /П[0-9]+/)) {
        ref = substr(s, RSTART, RLENGTH)
        s = substr(s, RSTART + RLENGTH)
        r = ref
        sub(/^П/, "", r)
        if (!((r + 0) in seen)) print "W" US order[k] US "П" (r + 0)
      }
    }
  }
' "$analysis") || {
  say "READ_FAILED $analysis"
  exit 6
}

has() { printf '%s\n' "$parsed" | grep -q "^$1"; }
field() { printf '%s\n' "$parsed" | awk -F "$us" -v k="$1" '$1 == k { print $2 }'; }

if ! has S6; then
  say "BAD_ANALYSIS $analysis section=6"
  exit 4
fi
if ! has S7; then
  say "BAD_ANALYSIS $analysis section=7"
  exit 4
fi
if has "Q$us"; then
  say "QUESTIONS_OPEN $task"
  field Q | sed 's/^/question=/'
  exit 4
fi
if has "E$us"; then
  say "BAD_TABLE $analysis"
  printf '%s\n' "$parsed" | awk -F "$us" '$1 == "E" { print "line=" $2 " " $3 }'
  exit 4
fi
if has "R$us" && has "NONE$us"; then
  say "BAD_TABLE $analysis"
  say "line=0 table-and-none"
  exit 4
fi
if has "NONE$us"; then
  say "NO_SPLIT $task"
  field NONE | sed 's/^/reason=/'
  exit 0
fi
if ! has "R$us"; then
  say "NO_TABLE $analysis"
  exit 4
fi

rows=$(printf '%s\n' "$parsed" | grep "^R$us")

# Файлы в подзадачи/: «NN_<имя>.md» — с номером, остальное — extra.
numbered=
extra=
if [ -d "$sub" ]; then
  for f in "$sub"/*; do
    [ -e "$f" ] || [ -L "$f" ] || continue
    b=${f##*/}
    entry_number "$b"
    if [ -f "$f" ] && [ -n "$entry_number" ]; then
      case $b in
        *_*.md)
          numbered="$numbered$entry_number$us$b
"
          continue
          ;;
      esac
    fi
    extra="${extra}extra $b
"
  done
fi

files_for() {
  printf '%s' "$numbered" | awk -F "$us" -v n="$1" '$1 == n { print $2 }'
}

# Строка раздела 7 так, как её хранит source: в шапке файла.
source_of() {
  printf 'П%s | %s | %s | %s | %s' "$1" "$2" "$3" "$4" "$5"
}

# Состояние каждой строки и карта номер → файл для ссылок «Зависит от».
plan=
map=
new_nums=
while IFS=$us read -r kind num title where deps size; do
  list=$(files_for "$num")
  count=0
  if [ -n "$list" ]; then
    count=$(printf '%s\n' "$list" | wc -l | tr -d ' ')
  fi
  if [ "$count" -eq 0 ]; then
    plan="${plan}П$num new $title
"
    new_nums="$new_nums $num"
    continue
  fi
  if [ "$count" -gt 1 ]; then
    plan="$plan$(printf '%s\n' "$list" | sed "s/^/П$num dup /")
"
    continue
  fi
  f=$sub/$list
  map="$map$num$us$list$us$title
"
  if [ "$(config_value "$f" sae)" != subtask ]; then
    plan="${plan}П$num foreign $list
"
    continue
  fi
  if grep -qF '<!-- заполнить' "$f"; then
    unfilled=yes
  else
    unfilled=no
  fi
  old=$(config_value "$f" source)
  now=$(source_of "$num" "$title" "$where" "$deps" "$size")
  if [ "$old" != "$now" ]; then
    plan="${plan}П$num changed $list
was=$old
now=$now
unfilled=$unfilled
"
  elif [ "$unfilled" = yes ]; then
    plan="${plan}П$num draft $list
"
  else
    plan="${plan}П$num ok $list
"
  fi
done <<EOF
$rows
EOF

gone=$(printf '%s' "$numbered" | while IFS=$us read -r n b; do
  printf '%s\n' "$rows" | awk -F "$us" -v n="$n" '$2 == n { found = 1 } END { exit found }' &&
    say "gone $b"
done)
warns=$(printf '%s\n' "$parsed" | awk -F "$us" '$1 == "W" { print "dep.missing=П" $2 " " $3 }')

if [ "$mode" = plan ]; then
  say "PLAN $task"
  printf '%s' "$plan"
  [ -n "$gone" ] && printf '%s\n' "$gone"
  printf '%s' "$extra"
  [ -n "$warns" ] && printf '%s\n' "$warns"
  exit 0
fi

# --create: аргументы <N>=<имя>; нужны ровно все строки «new».
given=
for arg in "$@"; do
  n=${arg%%=*}
  name=${arg#*=}
  case $arg in
    *=*) ;;
    *)
      say "BAD_ARG $arg"
      exit 2
      ;;
  esac
  case $n in
    '' | *[!0-9]*)
      say "BAD_ARG $arg"
      exit 2
      ;;
  esac
  n=$(expr "$n" + 0)
  check_name "$name" || exit 4
  case $name in
    *.md)
      say "BAD_NAME $name extension"
      exit 4
      ;;
  esac
  case " $given " in
    *" $n "*)
      say "DUP_ARG $n"
      exit 2
      ;;
  esac
  if ! printf '%s\n' "$rows" | awk -F "$us" -v n="$n" '$2 == n { found = 1 } END { exit !found }'; then
    say "NO_ROW $n"
    exit 4
  fi
  case " $new_nums " in
    *" $n "*) ;;
    *)
      state=$(printf '%s' "$plan" | awk -v p="П$n" '$1 == p { print $2; exit }')
      say "NOT_NEW П$n $state"
      exit 4
      ;;
  esac
  given="$given $n"
  file=$(printf '%02d' "$n")_$name.md
  if [ -e "$sub/$file" ] || [ -L "$sub/$file" ]; then
    say "EXISTS $sub/$file"
    exit 4
  fi
  title=$(printf '%s\n' "$rows" | awk -F "$us" -v n="$n" '$2 == n { print $3; exit }')
  map="$map$n$us$file$us$title
"
done
for n in $new_nums; do
  case " $given " in
    *" $n "*) ;;
    *)
      say "MISSING П$n"
      exit 4
      ;;
  esac
done

template=$(dirname "$0")/../templates/subtask.md
if [ ! -f "$template" ]; then
  say "NO_TEMPLATE $template"
  exit 5
fi

# Название задачи для ссылки.
task_title "$task"

if [ ! -d "$sub" ] && ! err=$(mkdir "$sub" 2>&1); then
  say "MKDIR_FAILED $sub"
  say "$err"
  exit 6
fi

created=
for n in $given; do
  row=$(printf '%s\n' "$rows" | awk -F "$us" -v n="$n" '$2 == n { print; exit }')
  IFS=$us read -r kind num title where deps size <<EOF
$row
EOF
  file=$(printf '%s' "$map" | awk -F "$us" -v n="$n" '$1 == n { print $2; exit }')
  dest=$sub/$file
  if ! err=$(TPL_SOURCE=$(source_of "$num" "$title" "$where" "$deps" "$size") \
    TPL_N=$num TPL_TITLE=$title TPL_TASK=$task_title TPL_WHERE=$where TPL_DEPS=$deps \
    TPL_SIZE=$size MAP=$map awk '
    # Текст ссылки внутри таблицы-паспорта: «[» и «]» — с «\»; «|» строки раздела 7 уже
    # экранирована, в названии задачи из задача.md — экранируется здесь.
    function link_text(s) { gsub(/[][]/, "\\\\&", s); return s }
    function cell_text(s) { gsub(/\\\|/, "\001", s); gsub(/\|/, "\\|", s); gsub(/\001/, "\\|", s); return s }
    function yaml(s) { gsub(/\047/, "\047\047", s); return "\047" s "\047" }
    function deps(s,    out, ref, r) {
      out = ""
      while (match(s, /П[0-9]+/)) {
        ref = substr(s, RSTART, RLENGTH)
        out = out substr(s, 1, RSTART - 1)
        s = substr(s, RSTART + RLENGTH)
        r = ref
        sub(/^П/, "", r)
        r = r + 0
        if (r in file) out = out "[" sprintf("%02d", r) " · " link_text(name[r]) "](" file[r] ")"
        else out = out ref
      }
      return out s
    }
    BEGIN {
      n = split(ENVIRON["MAP"], lines, "\n")
      for (i = 1; i <= n; i++) {
        if (split(lines[i], p, "\037") < 3) continue
        file[p[1]] = p[2]
        name[p[1]] = p[3]
      }
      v["SOURCE"] = yaml(ENVIRON["TPL_SOURCE"])
      v["N"] = ENVIRON["TPL_N"]
      v["TITLE"] = ENVIRON["TPL_TITLE"]
      gsub(/\\\|/, "|", v["TITLE"])
      v["TASK"] = link_text(cell_text(ENVIRON["TPL_TASK"]))
      v["WHERE"] = ENVIRON["TPL_WHERE"]
      v["DEPS"] = deps(ENVIRON["TPL_DEPS"])
      v["SIZE"] = ENVIRON["TPL_SIZE"]
    }
    {
      line = $0
      out = ""
      while (match(line, /__[A-Z]+__/)) {
        key = substr(line, RSTART + 2, RLENGTH - 4)
        out = out substr(line, 1, RSTART - 1)
        out = out ((key in v) ? v[key] : substr(line, RSTART, RLENGTH))
        line = substr(line, RSTART + RLENGTH)
      }
      print out line
    }
  ' "$template" 2>&1 >"$dest"); then
    rm -f "$dest"
    say "WRITE_FAILED $dest"
    say "$err"
    printf '%s' "$created"
    exit 6
  fi
  created="${created}file=$dest
"
done
say "CREATED $sub"
printf '%s' "$created"

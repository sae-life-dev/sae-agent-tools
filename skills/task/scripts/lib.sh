#!/bin/sh
# lib.sh — общее для скриптов скилла task. Подключается: . "$(dirname "$0")/lib.sh"
# Настройки проекта — .claude/sae.local.md в папке запуска Claude (рабочая папка скрипта),
# YAML-шапка с плоскими ключами вида task.dir. Папка задач помечена README.md с шапкой
# «sae: tasks». Функции, которые могут не сработать, печатают код итога и возвращают 1.

SAE_CONFIG=.claude/sae.local.md

here=$(pwd -P)

# Строка вывода как есть: echo в sh и dash раскрывает «\b», «\n» и т. п. в путях и именах.
say() {
  printf '%s\n' "$*"
}

# Путь как ввёл человек → абсолютный: раскрыть ~, относительный — от рабочей папки.
# Результат — в $abs_path.
abs_path() {
  case $1 in
    "~") abs_path=$HOME ;;
    "~/"*) abs_path=$HOME/${1#"~/"} ;;
    /*) abs_path=$1 ;;
    . | ./) abs_path=$here ;;
    ./*) abs_path=$here/${1#./} ;;
    *) abs_path=$here/$1 ;;
  esac
}

# Настоящий путь существующей папки, без ссылок и «..». Результат — в $physical_path.
physical() {
  physical_path=$(cd "$1" 2>/dev/null && pwd -P) && return 0
  say "CD_FAILED $1"
  return 1
}

# Папка помечена как папка задач: в шапке README.md есть строка «sae: tasks».
is_tasks_root() {
  [ -f "$1/README.md" ] || return 1
  awk '
    { sub(/\r$/, "") }
    NR == 1 && $0 != "---" { exit 1 }
    NR == 1 { next }
    $0 == "---" { closed = 1; exit }
    $0 == "sae: tasks" { found = 1 }
    END { exit !(closed && found) }
  ' "$1/README.md"
}

# Шапка файла настроек на месте: первая строка «---» и есть закрывающая «---».
config_well_formed() {
  awk '
    { sub(/\r$/, "") }
    NR == 1 && $0 != "---" { exit 1 }
    NR > 1 && $0 == "---" { closed = 1; exit }
    END { exit !closed }
  ' "$1"
}

# Значение ключа $2 из шапки файла $1; кавычки YAML снимаются. Нет ключа — пустая строка.
config_value() {
  KEY=$2 awk '
    { sub(/\r$/, "") }
    NR == 1 { if ($0 != "---") exit; next }
    $0 == "---" { exit }
    index($0, ENVIRON["KEY"] ":") == 1 {
      v = substr($0, length(ENVIRON["KEY"]) + 2)
      gsub(/^[ \t]+|[ \t]+$/, "", v)
      q = substr(v, 1, 1)
      if (length(v) >= 2 && (q == "\047" || q == "\"") && substr(v, length(v), 1) == q) {
        v = substr(v, 2, length(v) - 2)
        if (q == "\047") gsub(/\047\047/, "\047", v)
        else { gsub(/\\"/, "\"", v); gsub(/\\\\/, "\\", v) }
      }
      print v
      exit
    }
  ' "$1"
}

# Папка задач из настроек проекта. Успех — путь в $tasks_root.
tasks_root_from_config() {
  if [ ! -f "$here/$SAE_CONFIG" ]; then
    say "NO_CONFIG $here/$SAE_CONFIG"
    return 1
  fi
  value=$(config_value "$here/$SAE_CONFIG" task.dir)
  if [ -z "$value" ]; then
    say "CONFIG_NO_KEY $here/$SAE_CONFIG task.dir"
    return 1
  fi
  abs_path "$value"
  if [ ! -d "$abs_path" ]; then
    say "TASKS_MISSING $abs_path"
    return 1
  fi
  physical "$abs_path" || return 1
  if ! is_tasks_root "$physical_path"; then
    say "TASKS_UNMARKED $physical_path"
    return 1
  fi
  tasks_root=$physical_path
}

# Имя для записи «<номер>_<имя>»: без пробелов, «/», «\», не с «.» или «-» и не с номера —
# 1–3 цифры, за ними «_», «-» или конец (годы вроде «2024-…» — можно). Номер ставит скрипт.
# Не подошло — печатает BAD_NAME и возвращает 1.
check_name() {
  case $1 in
    *[[:space:]]* | */* | *\\* | .* | -*)
      say "BAD_NAME $1"
      return 1
      ;;
  esac
  lead=${1%%[!0-9]*}
  if [ -n "$lead" ] && [ ${#lead} -le 3 ]; then
    case ${1#"$lead"} in
      '' | _* | -*)
        say "BAD_NAME $1 number"
        return 1
        ;;
    esac
  fi
}

# Название задачи — заголовок «# …» задача.md без «Задача: »; нет — имя папки.
# $1 — папка задачи. Результат — в $task_title.
task_title() {
  task_title=
  if [ -f "$1/задача.md" ]; then
    task_title=$(awk '
      { sub(/\r$/, "") }
      /^# / { t = substr($0, 3); sub(/^[ \t]+/, "", t); sub(/^Задача:[ \t]*/, "", t); print t; exit }
    ' "$1/задача.md")
  fi
  [ -n "$task_title" ] || task_title=${1##*/}
}

# Разбор файла подзадачи: раздел «## 2.» — шаги «- [ ] N. …», раздел «## 3.» — признаки
# «- [ ] …»; «- [x]» — отмечено. Раздел кончается на «## » или «<details»; блоки ``` и ~~~
# пропускаются. Шаги должны идти с 1 подряд, иначе в $steps_bad — номер строки файла.
# Результат: $sub_status (done | open), $sub_draft (yes — остались метки «<!-- заполнить»),
# $steps_total, $steps_done, $step_first (первый неотмеченный шаг; все отмечены — пусто),
# $checks_total, $checks_done, $sub_scan — строки «S|C <\037> <строка файла> <\037> <номер>
# <\037> x| » для записи по номерам строк.
subtask_read() {
  if [ "$(config_value "$1" status)" = done ]; then
    sub_status=done
  else
    sub_status=open
  fi
  if grep -qF '<!-- заполнить' "$1"; then
    sub_draft=yes
  else
    sub_draft=no
  fi
  sub_scan=$(awk '
    BEGIN { US = "\037" }
    { sub(/\r$/, "") }
    /^[ \t]*(```|~~~)/ { fence = !fence; next }
    fence { next }
    /^## / {
      sec = ""
      if ($0 ~ /^## 2\./) sec = 2
      else if ($0 ~ /^## 3\./) sec = 3
      next
    }
    /^<details/ { sec = ""; next }
    sec == "" || $0 !~ /^- \[[ xX]\] / { next }
    {
      mark = (substr($0, 4, 1) == " ") ? " " : "x"
      if (sec == 3) { checks++; print "C" US NR US checks US mark; next }
      rest = substr($0, 7)
      num = ""
      if (match(rest, /^[0-9]+\. /)) num = substr(rest, 1, RLENGTH - 2) + 0
      print "S" US NR US num US mark
    }
  ' "$1")
  read -r steps_total steps_done step_first steps_bad checks_total checks_done <<EOF
$(printf '%s\n' "$sub_scan" | awk -F "\037" '
    $1 == "S" {
      total++
      if (!bad && $3 != total) bad = $2
      if ($4 == "x") done++
      else if (first == "") first = $3
    }
    $1 == "C" { ctotal++; if ($4 == "x") cdone++ }
    END { print total + 0, done + 0, (first == "" ? "-" : first), (bad ? bad : "-"), ctotal + 0, cdone + 0 }
  ')
EOF
  [ "$step_first" = - ] && step_first=
  [ "$steps_bad" = - ] && steps_bad=
  return 0
}

# Номер задачи из имени записи «NNN_…» без ведущих нулей; не номер — пустая строка.
# Результат — в $entry_number.
entry_number() {
  entry_number=${1##*/}
  entry_number=${entry_number%%_*}
  case $entry_number in
    '' | *[!0-9]*) entry_number= ;;
    *) entry_number=$(expr "$entry_number" + 0) ;;
  esac
}

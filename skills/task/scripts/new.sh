#!/bin/sh
# new.sh <имя> <название> [<ключ Jira>] — заводит в папке задач <NNN>_<имя>/задача.md,
# с ключом — <NNN>_<КЛЮЧ>_<имя>/задача.md и строку «**Jira:** <КЛЮЧ>» под заголовком.
# Папка задач — из настроек проекта (.claude/sae.local.md в рабочей папке, ключ task.dir).
# Номер — наибольший NNN среди записей «NNN_…» (папок и файлов) в папке задач и в служебных
# папках «_…» (архив) плюс один. Ключ — вида ABC-123 (латиница заглавными, цифры, «_», дефис,
# номер); тот же ключ у другой задачи (в имени папки или в строке «**Jira:**») не мешает.
# Первая строка вывода — итог: CREATED, BAD_NAME, BAD_JIRA, NO_ARG, код из настроек (NO_CONFIG,
# CONFIG_NO_KEY, TASKS_MISSING, TASKS_UNMARKED) или код сбоя; при сбое следом — текст системной
# ошибки. После CREATED — по строке jira.dup=<папка> на каждую задачу с тем же ключом.
# Ничего, кроме новой папки задачи, не создаёт и не трогает.
set -u
. "$(dirname "$0")/lib.sh"

if [ $# -lt 2 ] || [ -z "$1" ] || [ -z "$2" ]; then
  say "NO_ARG"
  exit 2
fi

name=$1
title=$2
if [ $# -ge 3 ]; then
  jira=$3
  jira_given=1
else
  jira=
  jira_given=0
fi

check_name "$name" || exit 4
case $title in
  *"
"*)
    say "BAD_NAME title-multiline"
    exit 4
    ;;
esac
# Ключ Jira: <ПРОЕКТ>-<номер>, проект — с заглавной латинской буквы. Буквы перечислены явно:
# диапазон [A-Z] в части локалей захватывает строчные.
if [ "$jira_given" -eq 1 ]; then
  jira_project=${jira%-*}
  jira_number=${jira##*-}
  jira_ok=1
  case $jira in
    *-*) ;;
    *) jira_ok=0 ;;
  esac
  case $jira_project in
    [ABCDEFGHIJKLMNOPQRSTUVWXYZ]*) ;;
    *) jira_ok=0 ;;
  esac
  case $jira_project in
    *[!ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_]*) jira_ok=0 ;;
  esac
  case $jira_number in
    '' | *[!0123456789]*) jira_ok=0 ;;
  esac
  if [ "$jira_ok" -eq 0 ]; then
    say "BAD_JIRA${jira:+ $jira}"
    exit 4
  fi
fi

tasks_root_from_config || exit 3
root=$tasks_root

template=$(dirname "$0")/../templates/task.md
if [ ! -f "$template" ]; then
  say "NO_TEMPLATE $template"
  exit 5
fi

# Задача с тем же ключом: ключ в имени папки «NNN_<КЛЮЧ>_…» или строка «**Jira:** <КЛЮЧ>»
# в её задача.md.
has_jira() {
  rest=${1##*/}
  rest=${rest#*_}
  case $rest in
    "$jira"_*) return 0 ;;
  esac
  [ -f "$1/задача.md" ] || return 1
  KEY=$jira awk '
    { sub(/\r$/, ""); gsub(/^[ \t]+|[ \t]+$/, "") }
    index($0, "**Jira:**") == 1 {
      v = substr($0, 10)
      gsub(/^[ \t]+/, "", v)
      if (v == ENVIRON["KEY"]) { found = 1; exit }
    }
    END { exit !found }
  ' "$1/задача.md"
}

max=0
dups=
for d in "$root"/[0-9]*_* "$root"/_*/[0-9]*_*; do
  [ -e "$d" ] || [ -L "$d" ] || continue
  entry_number "$d"
  [ -n "$entry_number" ] || continue
  if [ "$entry_number" -gt "$max" ]; then
    max=$entry_number
  fi
  if [ -n "$jira" ] && [ -d "$d" ] && has_jira "$d"; then
    dups="${dups}jira.dup=$d
"
  fi
done
num=$(printf '%03d' $((max + 1)))

dir=$root/${num}_${jira:+${jira}_}$name
if ! err=$(mkdir "$dir" 2>&1); then
  say "MKDIR_FAILED $dir"
  say "$err"
  exit 6
fi
# Строка «__JIRA__» шаблона: с ключом — «**Jira:** <КЛЮЧ>», без ключа — убирается вместе
# с пустой строкой за ней.
if ! err=$(TITLE=$title JIRA=$jira awk '
  skip_blank { skip_blank = 0; if ($0 == "") next }
  $0 == "__JIRA__" {
    if (ENVIRON["JIRA"] == "") { skip_blank = 1; next }
    print "**Jira:** " ENVIRON["JIRA"]
    next
  }
  {
    out = ""
    while ((i = index($0, "__TITLE__")) > 0) {
      out = out substr($0, 1, i - 1) ENVIRON["TITLE"]
      $0 = substr($0, i + 9)
    }
    print out $0
  }
' "$template" 2>&1 >"$dir/задача.md"); then
  rm -f "$dir/задача.md"
  rmdir "$dir"
  say "WRITE_FAILED $dir/задача.md"
  say "$err"
  exit 6
fi
say "CREATED $dir"
printf '%s' "$dups"

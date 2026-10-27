#!/bin/sh
# lib.sh — общее для тестов скриптов скилла task. Подключается: . "$(dirname "$0")/lib.sh"
# Тест работает на копии tests/fixtures/ во временной папке: fresh делает свежую копию и
# переходит в неё (скрипты берут .claude/sae.local.md из рабочей папки); оригинал образцов
# и настоящая папка задач не меняются. Копия удаляется при выходе.
# check <имя> <код> <команда…> — ожидаемый вывод на stdin (heredoc); сравнивается весь вывод
# (stdout и stderr) и код выхода; путь копии в выводе заменяется на <ROOT>.
# finish — итог «RESULT <файл> passed=N failed=M», код выхода не 0, если что-то упало.
set -u

tests_dir=$(cd "$(dirname "$0")" && pwd -P) || exit 1
scripts=$(cd "$tests_dir/../skills/task/scripts" && pwd -P) || exit 1
fixtures=$tests_dir/fixtures

passed=0
failed=0

work=$(mktemp -d) || exit 1
work=$(cd "$work" && pwd -P) || exit 1
trap 'rm -rf "$work"' EXIT
trap 'exit 1' HUP INT TERM

say() {
  printf '%s\n' "$*"
}

# Свежая копия образцов в $work/root; рабочая папка — она, путь — в $root.
# .DS_Store, которые кладёт Finder, в копии удаляются: split.sh посчитал бы их extra.
fresh() {
  cd "$work" || exit 1
  rm -rf root
  cp -R "$fixtures" root || exit 1
  find root -name .DS_Store -exec rm -f {} + || exit 1
  cd root || exit 1
  root=$(pwd -P)
}

# Путь копии → <ROOT>, чтобы ожидаемый вывод не зависел от временной папки.
mask() {
  ROOT=$root awk '
    {
      s = $0
      out = ""
      r = ENVIRON["ROOT"]
      while ((i = index(s, r)) > 0) {
        out = out substr(s, 1, i - 1) "<ROOT>"
        s = substr(s, i + length(r))
      }
      print out s
    }
  '
}

check() {
  name=$1
  want_code=$2
  shift 2
  want=$(cat)
  got=$("$@" </dev/null 2>&1)
  code=$?
  got=$(printf '%s\n' "$got" | mask)
  if [ "$code" = "$want_code" ] && [ "$got" = "$want" ]; then
    passed=$((passed + 1))
    say "ok   $name"
    return 0
  fi
  failed=$((failed + 1))
  say "FAIL $name"
  [ "$code" = "$want_code" ] || say "     код выхода: ждали $want_code, получили $code"
  if [ "$got" != "$want" ]; then
    printf '%s\n' "$want" >"$work/want"
    printf '%s\n' "$got" >"$work/got"
    diff "$work/want" "$work/got" | sed 's/^/     /'
  fi
  return 0
}

finish() {
  say "RESULT ${0##*/} passed=$passed failed=$failed"
  [ "$failed" -eq 0 ]
}

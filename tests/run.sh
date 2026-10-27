#!/bin/sh
# run.sh — все проверки плагина: claude plugin validate --strict (marketplace.json по корню
# репозитория и .claude-plugin/plugin.json), check_version.sh, затем каждый tests/test_*.sh.
# Прогон не останавливается на первом падении. Итог — «TOTAL tests passed=N failed=M
# validate=K/2 files=F/G version=ok|bumped|warn|skip»; код выхода не 0, если упало хоть что-то.
# Предупреждение о версии код выхода не меняет.
# Файл теста засчитывается упавшим, если в выводе нет строки RESULT или код выхода не 0 при failed=0.
set -u

tests_dir=$(cd "$(dirname "$0")" && pwd -P) || exit 1
repo=$(cd "$tests_dir/.." && pwd -P) || exit 1

passed=0
failed=0
validate_ok=0
files_ok=0
files=0
bad=0

say() {
  printf '%s\n' "$*"
}

validate() {
  name=$1
  target=$2
  if ! command -v claude >/dev/null 2>&1; then
    say "FAIL validate $name"
    say "     команда claude не найдена"
    bad=1
    return 0
  fi
  out=$(claude plugin validate --strict "$target" </dev/null 2>&1)
  code=$?
  if [ "$code" -eq 0 ]; then
    validate_ok=$((validate_ok + 1))
    say "ok   validate $name"
    return 0
  fi
  bad=1
  say "FAIL validate $name (код $code)"
  printf '%s\n' "$out" | sed 's/^/     /'
  return 0
}

validate marketplace.json "$repo"
validate plugin.json "$repo/.claude-plugin/plugin.json"

say ""
out=$(sh "$tests_dir/check_version.sh" "$repo" </dev/null 2>&1)
printf '%s\n' "$out"
case $(printf '%s\n' "$out" | head -n 1) in
  "WARN version"*) version=warn ;;
  "VERSION ok"*) version=ok ;;
  "VERSION bumped"*) version=bumped ;;
  *) version=skip ;;
esac

for t in "$tests_dir"/test_*.sh; do
  [ -f "$t" ] || continue
  files=$((files + 1))
  say ""
  out=$(sh "$t" </dev/null 2>&1)
  code=$?
  printf '%s\n' "$out"
  line=$(printf '%s\n' "$out" | grep '^RESULT ' | tail -n 1)
  p=$(printf '%s\n' "$line" | sed -n 's/.* passed=\([0-9][0-9]*\) failed=\([0-9][0-9]*\)$/\1/p')
  f=$(printf '%s\n' "$line" | sed -n 's/.* passed=\([0-9][0-9]*\) failed=\([0-9][0-9]*\)$/\2/p')
  if [ -z "$p" ] || [ -z "$f" ]; then
    bad=1
    say "FAIL ${t##*/}: нет строки RESULT (код $code)"
    continue
  fi
  passed=$((passed + p))
  failed=$((failed + f))
  if [ "$code" -ne 0 ] && [ "$f" -eq 0 ]; then
    bad=1
    say "FAIL ${t##*/}: код $code при failed=0"
    continue
  fi
  [ "$f" -eq 0 ] && files_ok=$((files_ok + 1))
done

[ "$files" -gt 0 ] || { bad=1; say "FAIL нет файлов tests/test_*.sh"; }
[ "$failed" -eq 0 ] || bad=1

say ""
say "TOTAL tests passed=$passed failed=$failed validate=$validate_ok/2 files=$files_ok/$files version=$version"
[ "$bad" -eq 0 ]

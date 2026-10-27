#!/bin/sh
# check_version.sh [репозиторий] — правило версии: установленные копии плагина обновляются, только
# когда меняется version в .claude-plugin/plugin.json. Точка сравнения — последний коммит, где
# менялась строка "version". Если с него изменились файлы skills/ или .claude-plugin/ (в коммитах,
# в рабочем дереве или новые вне git; .DS_Store не в счёт), а version та же — предупреждение.
# Первая строка вывода: «VERSION ok …», «VERSION bumped …», «VERSION skip …» или «WARN version …»
# (за ней — изменённые файлы). Код выхода всегда 0: это предупреждение, а не падение.
# Без аргумента проверяется репозиторий, в котором лежит tests/.
set -u

tests_dir=$(cd "$(dirname "$0")" && pwd -P) || exit 1
repo=${1:-$tests_dir/..}
repo=$(cd "$repo" && pwd -P) || exit 1
manifest=.claude-plugin/plugin.json

say() {
  printf '%s\n' "$*"
}

version_of() {
  sed -n 's/^[[:space:]]*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1
}

if ! git -C "$repo" rev-parse --git-dir >/dev/null 2>&1; then
  say "VERSION skip: $repo — не git-репозиторий"
  exit 0
fi

base=$(git -C "$repo" log -1 --format=%h -G'"version"' -- "$manifest" 2>/dev/null)
if [ -z "$base" ]; then
  say "VERSION skip: нет коммита, где менялась version в $manifest"
  exit 0
fi

old=$(git -C "$repo" show "$base:$manifest" 2>/dev/null | version_of)
new=$(version_of < "$repo/$manifest")

if [ "$old" != "$new" ]; then
  say "VERSION bumped: $old -> $new (с коммита $base)"
  exit 0
fi

changed=$( {
  git -C "$repo" -c core.quotepath=off diff --name-only "$base" -- skills .claude-plugin
  git -C "$repo" -c core.quotepath=off ls-files --others --exclude-standard -- skills .claude-plugin
} | grep -v -e '^\.DS_Store$' -e '/\.DS_Store$' | sort -u)

if [ -z "$changed" ]; then
  say "VERSION ok: с коммита $base файлы плагина не менялись (version $new)"
  exit 0
fi

say "WARN version: файлы плагина изменились с коммита $base, а version всё ещё '$new' — подними version в $manifest"
printf '%s\n' "$changed" | sed 's/^/     /'
exit 0

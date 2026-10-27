#!/bin/sh
# check_version.sh [репозиторий] — правило версии: установленные копии плагина обновляются, только
# когда меняется version в его манифесте plugins/<имя>/.claude-plugin/plugin.json. Проверяется каждый
# подплагин отдельно; точка сравнения — последний коммит, где менялась строка "version" его манифеста.
# Если с него изменились файлы подплагина (в коммитах, в рабочем дереве или новые вне git;
# .DS_Store не в счёт), а version та же — предупреждение. Первая строка по каждому подплагину:
# «VERSION ok …», «VERSION bumped …», «VERSION skip …» или «WARN version …» (за ней — изменённые
# файлы). Код выхода всегда 0: это предупреждение, а не падение. Без аргумента проверяется
# репозиторий, в котором лежит tests/.
set -u

tests_dir=$(cd "$(dirname "$0")" && pwd -P) || exit 1
repo=${1:-$tests_dir/..}
repo=$(cd "$repo" && pwd -P) || exit 1

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

for manifest in "$repo"/plugins/*/.claude-plugin/plugin.json; do
  [ -f "$manifest" ] || continue
  rel=${manifest#"$repo"/}

  base=$(git -C "$repo" log -1 --format=%h -G'"version"' -- "$rel" 2>/dev/null)
  if [ -z "$base" ]; then
    say "VERSION skip: $rel — нет коммита, где менялась version"
    continue
  fi

  old=$(git -C "$repo" show "$base:$rel" 2>/dev/null | version_of)
  new=$(version_of < "$manifest")

  if [ "$old" != "$new" ]; then
    say "VERSION bumped: $rel $old -> $new (с коммита $base)"
    continue
  fi

  plugin_root=${rel%/.claude-plugin/plugin.json}
  changed=$( {
    git -C "$repo" -c core.quotepath=off diff --name-only "$base" -- "$plugin_root" .claude-plugin
    git -C "$repo" -c core.quotepath=off ls-files --others --exclude-standard -- "$plugin_root" .claude-plugin
  } | grep -v -e '^\.DS_Store$' -e '/\.DS_Store$' | sort -u)

  if [ -z "$changed" ]; then
    say "VERSION ok: $rel — с коммита $base файлы плагина не менялись (version $new)"
    continue
  fi

  say "WARN version: $rel — файлы плагина изменились с коммита $base, а version всё ещё '$new' — подними version"
  printf '%s\n' "$changed" | sed 's/^/     /'
done
exit 0

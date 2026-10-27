#!/bin/sh
# init.sh [--replace-config] <путь> — делает <путь> папкой задач и записывает его в настройки
# проекта (.claude/sae.local.md в рабочей папке, ключ task.dir).
# Папки нет — создаётся только последний уровень пути. Пустая папка — помечается. Непустая без
# метки — не трогается. Другой task.dir в настройках без --replace-config — не трогается ничего.
# Первая строка вывода — итог: CREATED, MARKED, EXISTS или код отказа/сбоя; дальше — строки
# «ключ=значение». Сбой: сначала код, следом текст системной ошибки.
set -u
. "$(dirname "$0")/lib.sh"

replace=no
if [ "${1-}" = "--replace-config" ]; then
  replace=yes
  shift
fi
if [ $# -lt 1 ] || [ -z "$1" ]; then
  say "NO_ARG"
  exit 2
fi

config=$here/$SAE_CONFIG

# Проверки до любых изменений: настройки, затем папка.
if [ -e "$here/.claude" ] && [ ! -d "$here/.claude" ]; then
  say "CONFIG_BAD $here/.claude"
  say "reason=not-dir"
  exit 4
fi
old=
if [ -e "$config" ]; then
  if [ ! -f "$config" ] || ! config_well_formed "$config"; then
    say "CONFIG_BAD $config"
    say "reason=no-front-matter"
    exit 4
  fi
  old=$(config_value "$config" task.dir)
fi

abs_path "$1"
target=$abs_path
if [ -e "$target" ]; then
  if [ ! -d "$target" ]; then
    say "NOT_DIR $target"
    exit 3
  fi
  physical "$target" || exit 3
  root=$physical_path
  if is_tasks_root "$root"; then
    action=exists
  elif [ -z "$(ls -A "$root" | awk '$0 != ".DS_Store"')" ]; then
    action=mark
  else
    say "NOT_EMPTY $root"
    ls -A "$root"
    exit 4
  fi
else
  parent=$(dirname "$target")
  if [ ! -d "$parent" ]; then
    say "NO_PARENT $parent"
    exit 3
  fi
  physical "$parent" || exit 3
  leaf=$(basename "$target")
  case $physical_path in
    /) root=/$leaf ;;
    *) root=$physical_path/$leaf ;;
  esac
  action=create
fi

template=$(dirname "$0")/../templates/README.md
if [ "$action" != exists ] && [ ! -f "$template" ]; then
  say "NO_TEMPLATE $template"
  exit 5
fi

# Что писать в task.dir: путь от рабочей папки, если папка задач внутри неё, иначе абсолютный.
if [ "$here" = / ]; then
  value=${root#/}
else
  case $root in
    "$here") value=. ;;
    "$here"/*) value=${root#"$here"/} ;;
    *) value=$root ;;
  esac
fi

if [ -n "$old" ]; then
  abs_path "$old"
  old_root=$abs_path
  if [ -d "$old_root" ] && physical "$old_root" >/dev/null; then
    old_root=$physical_path
  fi
  if [ "$old_root" = "$root" ]; then
    config_action=same
  elif [ "$replace" = yes ]; then
    config_action=replaced
  else
    say "CONFIG_DIFFERENT $config"
    say "task.dir.old=$old"
    say "task.dir=$value"
    exit 4
  fi
else
  config_action=written
fi

# Значение в YAML: без кавычек, если это безопасно; иначе в одинарных, ' удваивается.
quote=no
case ${value%"${value#?}"} in
  - | '?' | : | , | '[' | ']' | '{' | '}' | '#' | '&' | '*' | ! | '|' | '>' | "'" | '"' | % | @ | '`' | ' ')
    quote=yes
    ;;
esac
tab=$(printf '\t')
case $value in
  *' ' | *: | *': '* | *' #'* | *"$tab"*) quote=yes ;;
esac
if [ "$quote" = yes ]; then
  yaml_value="'$(printf '%s' "$value" | sed "s/'/''/g")'"
else
  yaml_value=$value
fi

# Запись task.dir: новый файл — с шапкой и пояснением; существующий — замена или вставка ключа
# в шапку, остальное не трогается. Пишется во временный файл и переносится на место.
write_config() {
  err=$(mkdir -p "$here/.claude" 2>&1) || return 1
  tmp=$config.tmp.$$
  if [ -f "$config" ]; then
    err=$(LINE="task.dir: $yaml_value" awk '
      { sub(/\r$/, "") }
      NR == 1 { print; next }
      !closed && index($0, "task.dir:") == 1 { if (!done) print ENVIRON["LINE"]; done = 1; next }
      !closed && $0 == "---" { if (!done) print ENVIRON["LINE"]; done = 1; closed = 1 }
      { print }
    ' "$config" 2>&1 >"$tmp") || { rm -f "$tmp"; return 1; }
  else
    err=$(printf '%s\n' \
      "---" \
      "task.dir: $yaml_value" \
      "---" \
      "" \
      "Настройки плагина sae для этого проекта. Файл личный: держите его вне git" \
      "(строка \`.claude/*.local.md\` в \`.gitignore\`)." 2>&1 >"$tmp") || { rm -f "$tmp"; return 1; }
  fi
  err=$(mv "$tmp" "$config" 2>&1) || { rm -f "$tmp"; return 1; }
}

# Изменения: папка и метка, затем настройки.
if [ "$action" = create ]; then
  if ! err=$(mkdir "$root" 2>&1); then
    say "MKDIR_FAILED $root"
    say "$err"
    exit 6
  fi
fi
if [ "$action" != exists ]; then
  if ! err=$(sed "s/__DATE__/$(date +%Y-%m-%d)/" "$template" 2>&1 >"$root/README.md"); then
    rm -f "$root/README.md"
    [ "$action" = create ] && rmdir "$root"
    say "WRITE_FAILED $root/README.md"
    say "$err"
    exit 6
  fi
fi
if [ "$config_action" != same ] && ! write_config; then
  say "CONFIG_FAILED $config"
  say "$err"
  say "folder=$action $root"
  exit 6
fi

case $action in
  create) say "CREATED $root" ;;
  mark) say "MARKED $root" ;;
  exists) say "EXISTS $root" ;;
esac
say "config=$config_action"
say "config.file=$config"
say "task.dir=$value"
if [ "$config_action" = replaced ]; then
  say "task.dir.old=$old"
fi
if ! command -v git >/dev/null 2>&1; then
  say "git=no-git"
elif ! git -C "$here" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  say "git=no-repo"
elif git -C "$here" check-ignore -q "$SAE_CONFIG"; then
  say "git=ignored"
else
  say "git=not-ignored"
fi

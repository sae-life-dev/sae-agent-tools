#!/bin/sh
# links.sh <файл> [<проект Jira>] — ссылки из текста задачи Jira или исходника статьи КБ
# (confluence_get_page с convert_to_markdown=false: в markdown ссылки на страницы теряются).
# Файл — ответ MCP, сохранённый Claude Code (JSON; строки внутри, в том числе вложенный JSON,
# разворачиваются), или любой текст. Проект Jira (MS) — ещё и голые ключи «MS-123» в тексте.
# Адреса Jira и КБ — из .env MCP-сервера (ключ atlassian.env), если он настроен: по ним
# отделяются внешние ссылки.
# Вывод — строки без повторов и без ссылки на сам объект (по папке файла):
#   kb.id <id>                        pageId=…, /pages/<id>, data-linked-resource-id
#   kb.title <пространство|-> <название>  <ri:page …> и /display/<пространство>/<название>
#   kb.tiny <ссылка>                  короткие /x/…
#   jira <КЛЮЧ>                       /browse/КЛЮЧ, макрос jira, голые ключи проекта
#   url <ссылка>                      остальные http(s)
# Первая строка — итог: LINKS <число строк>, NO_FILE, NO_ARG. Ничего не меняет.
set -u
. "$(dirname "$0")/lib.sh"

if [ $# -lt 1 ] || [ -z "$1" ]; then
  say "NO_ARG"
  exit 2
fi
if [ ! -f "$1" ]; then
  say "NO_FILE $1"
  exit 3
fi
project=${2:-}

jira_url=
kb_url=
if atlassian_env_from_config >/dev/null 2>&1; then
  jira_url=$(env_value "$atl_env" JIRA_URL)
  kb_url=$(env_value "$atl_env" CONFLUENCE_URL)
  jira_url=${jira_url%/}
  kb_url=${kb_url%/}
fi

work=$(mktemp -d "${TMPDIR:-/tmp}/sae-links.XXXXXX") || exit 6
trap 'rm -rf "$work"' EXIT

# Текст: строки JSON, вложенный JSON в строках — тоже; не JSON — файл как есть.
if command -v jq >/dev/null 2>&1 && jq -e . "$1" >/dev/null 2>&1; then
  jq -r '
    def flat: if type == "string" then (. as $s | try (fromjson | flat) catch $s)
              elif type == "array" or type == "object" then (.[] | flat)
              else empty end;
    flat | strings
  ' "$1" >"$work/text"
else
  cp "$1" "$work/text"
fi
# HTML-сущности в атрибутах и тексте.
sed -e 's/&quot;/"/g' -e "s/&#39;/'/g" -e 's/&lt;/</g' -e 's/&gt;/>/g' -e 's/&amp;/\&/g' \
  "$work/text" >"$work/t"

: >"$work/out"

grep -oE 'pageId=[0-9]+' "$work/t" | sed 's/^pageId=/kb.id /' >>"$work/out"
grep -oE '/pages/[0-9]+' "$work/t" | sed 's|^/pages/|kb.id |' >>"$work/out"
grep -oE 'data-linked-resource-id="[0-9]+"[^>]*data-linked-resource-type="page"' "$work/t" |
  sed -E 's/^data-linked-resource-id="([0-9]+)".*/kb.id \1/' >>"$work/out"

# <ri:page ri:space-key="X" ri:content-title="T" /> — порядок атрибутов любой.
grep -oE '<ri:page [^>]*>' "$work/t" | awk '
  function attr(s, name,   i, r) {
    i = index(s, name "=\"")
    if (i == 0) return ""
    r = substr(s, i + length(name) + 2)
    return substr(r, 1, index(r, "\"") - 1)
  }
  {
    t = attr($0, "ri:content-title")
    if (t == "") next
    sp = attr($0, "ri:space-key")
    print "kb.title " (sp == "" ? "-" : sp) " " t
  }
' >>"$work/out"

grep -oE '/display/[A-Za-z0-9~_-]+/[^]["<> )|]+' "$work/t" | while IFS= read -r d; do
  rest=${d#/display/}
  space=${rest%%/*}
  title=${rest#*/}
  title=${title%%\?*}
  title=${title%%#*}
  title=$(printf '%s' "$title" | tr '+' ' ')
  url_decode "$title"
  [ -n "$url_decoded" ] && say "kb.title $space $url_decoded"
done >>"$work/out"

grep -oE 'https?://[^ "<>)|]*/x/[A-Za-z0-9_-]+' "$work/t" | sed 's/^/kb.tiny /' >>"$work/out"

grep -oE '/browse/[A-Z][A-Z0-9_]+-[0-9]+' "$work/t" | sed 's|^/browse/|jira |' >>"$work/out"
grep -oE 'ac:name="key">[A-Z][A-Z0-9_]+-[0-9]+<' "$work/t" |
  sed -E 's/^ac:name="key">(.*)<$/jira \1/' >>"$work/out"
if [ -n "$project" ]; then
  grep -oE "(^|[^A-Za-z0-9_-])$project-[0-9]+" "$work/t" |
    sed -E "s/^.*($project-[0-9]+)$/jira \1/" >>"$work/out"
fi

# Внешние: http(s), кроме Jira и КБ (они уже разобраны выше).
grep -oE 'https?://[^] "<>)|]+' "$work/t" | sed -E 's/[.,;:]+$//' | while IFS= read -r u; do
  if [ -n "$jira_url" ]; then
    case $u in "$jira_url" | "$jira_url"/*) continue ;; esac
  fi
  if [ -n "$kb_url" ]; then
    case $u in "$kb_url" | "$kb_url"/*) continue ;; esac
  fi
  case $u in
    *pageId=* | */display/* | */browse/* | */x/*) continue ;;
  esac
  say "url $u"
done >>"$work/out"

# Сам объект — по папке файла (jira/<КЛЮЧ>/, кб/<id>_…/): ссылку на себя не выдавать.
self=
base=$(basename "$(dirname "$1")")
if printf '%s\n' "$base" | grep -qE '^[A-Z][A-Z0-9_]+-[0-9]+$'; then
  self="jira $base"
elif printf '%s\n' "$base" | grep -qE '^[0-9]+_'; then
  self="kb.id ${base%%_*}"
fi
awk -v self="$self" '$0 != self && !seen[$0]++' "$work/out" >"$work/uniq"
say "LINKS $(wc -l <"$work/uniq" | tr -d ' ')"
cat "$work/uniq"

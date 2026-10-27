#!/bin/sh
# decode.sh <ответ MCP> <папка> — достаёт вложения из ответа jira_download_attachments, который
# Claude Code сохранил в файл (tool-results/…), и кладёт их в папку материалов. Берёт части
# с base64: текст-JSON с полями filename и content (encoding base64) и ресурсы с blob (имя —
# из конца uri). Папка должна лежать внутри «…/материалы/».
# Первая строка вывода — итог: DECODED <число файлов>, NONE, NO_FILE, NOT_JSON, NOT_MATERIALS,
# NO_ARG или код сбоя. Затем на каждый файл — строки place: SAVED|SAME <путь>, size=<байт>.
# Нужен jq.
set -u
. "$(dirname "$0")/lib.sh"

if [ $# -lt 2 ] || [ -z "$1" ] || [ -z "$2" ]; then
  say "NO_ARG"
  exit 2
fi
if [ ! -f "$1" ]; then
  say "NO_FILE $1"
  exit 3
fi
abs_path "$2"
case $abs_path/ in
  */материалы/*) ;;
  *)
    say "NOT_MATERIALS $abs_path"
    exit 3
    ;;
esac
dest=$abs_path
if ! command -v jq >/dev/null 2>&1; then
  say "NO_JQ"
  exit 5
fi
if ! jq -e . "$1" >/dev/null 2>&1; then
  say "NOT_JSON $1"
  exit 4
fi

work=$(mktemp -d "${TMPDIR:-/tmp}/sae-decode.XXXXXX") || exit 6
trap 'rm -rf "$work"' EXIT

# Части ответа → строки «<имя>\t<base64>». Ответ — массив частей или одна часть.
jq -r '
  (if type == "array" then .[] else . end)
  | if .type == "text" then
      (.text | try fromjson catch null)
      | select(type == "object" and .encoding == "base64" and .filename and .content)
      | [.filename, .content]
    elif .type == "resource" and .resource.blob then
      [(.resource.uri | split("/") | last), .resource.blob]
    else empty end
  | @tsv
' "$1" >"$work/list" || {
  say "NOT_JSON $1"
  exit 4
}

count=0
out=
while IFS="$(printf '\t')" read -r name data; do
  [ -n "$name" ] || continue
  # Имя из uri приходит в %-кодировке; из filename — как есть.
  url_decode "$name"
  name=$url_decoded
  count=$((count + 1))
  printf '%s' "$data" | base64 -d >"$work/$count" 2>/dev/null || {
    out="${out}DECODE_FAILED $name
"
    continue
  }
  if ! res=$(place_file "$work/$count" "$dest" "$name"); then
    out="$out$res
"
    continue
  fi
  out="$out$res
"
done <"$work/list"

if [ "$count" -eq 0 ]; then
  say "NONE $1"
  exit 0
fi
say "DECODED $count"
printf '%s' "$out"

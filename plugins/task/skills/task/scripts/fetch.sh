#!/bin/sh
# fetch.sh <ссылка> <папка> <имя> [<размер>] — скачивает вложение curl'ом, когда MCP не кладёт
# его на диск сам (маленькие не-картинки Jira, файлы больше 50 МБ). Адреса и токены — из .env
# MCP-сервера Atlassian (ключ atlassian.env в .claude/sae.local.md: JIRA_URL,
# JIRA_PERSONAL_TOKEN, CONFLUENCE_URL, CONFLUENCE_PERSONAL_TOKEN). Токен уходит только на свой
# адрес: ссылка не с JIRA_URL и не с CONFLUENCE_URL — FOREIGN_HOST, ничего не качается.
# Ссылка «/download/…» без адреса — от CONFLUENCE_URL. Папка — внутри «…/материалы/».
# Первая строка вывода — итог: SAVED, SAME, FOREIGN_HOST, NO_TOKEN, DOWNLOAD_FAILED,
# NOT_MATERIALS, NO_ARG, код из настроек (NO_CONFIG, CONFIG_NO_KEY, ENV_MISSING) или код сбоя;
# следом size=<байт>. Токен не печатает.
set -u
. "$(dirname "$0")/lib.sh"

if [ $# -lt 3 ] || [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ]; then
  say "NO_ARG"
  exit 2
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

atlassian_env_from_config || exit 3
jira_url=$(env_value "$atl_env" JIRA_URL)
kb_url=$(env_value "$atl_env" CONFLUENCE_URL)
jira_url=${jira_url%/}
kb_url=${kb_url%/}

url=$1
case $url in
  /*) url=$kb_url$url ;;
esac

token=
if [ -n "$jira_url" ]; then
  case $url in
    "$jira_url"/*) token=$(env_value "$atl_env" JIRA_PERSONAL_TOKEN) ;;
  esac
fi
if [ -z "$token" ] && [ -n "$kb_url" ]; then
  case $url in
    "$kb_url"/*) token=$(env_value "$atl_env" CONFLUENCE_PERSONAL_TOKEN) ;;
    *) ;;
  esac
fi
case $url in
  "$jira_url"/* | "$kb_url"/*) ;;
  *)
    say "FOREIGN_HOST $url"
    exit 4
    ;;
esac
if [ -z "$token" ]; then
  say "NO_TOKEN $url"
  exit 4
fi

work=$(mktemp -d "${TMPDIR:-/tmp}/sae-fetch.XXXXXX") || exit 6
trap 'rm -rf "$work"' EXIT

# Заголовок с токеном — через stdin, чтобы токена не было в списке процессов.
if ! err=$(printf 'Authorization: Bearer %s\n' "$token" |
  curl -fsSL -H @- -o "$work/file" "$url" 2>&1); then
  say "DOWNLOAD_FAILED $url"
  say "$err"
  exit 6
fi

place_file "$work/file" "$dest" "$3" "${4:-}" || exit 6

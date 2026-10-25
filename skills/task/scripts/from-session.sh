#!/bin/sh
# from-session.sh <сессия> <вид> <ключ|id> <папка> — ответ MCP, который пришёл в разговор (не в
# файл), достаёт из журнала сессии побайтно и отдаёт render.sh: перепечатывать его не нужно.
# Сессия — id (журнал ищется в ~/.claude/projects/*/<id>.jsonl) или путь к журналу .jsonl.
# Вид и вызов, чей ответ берётся (последний такой в журнале):
#   jira        — jira_get_issue с issue_key <ключ>;
#   kb          — confluence_get_page с page_id <id>, кроме convert_to_markdown=false;
#   kb-raw      — confluence_get_page с page_id <id> и convert_to_markdown=false;
#   kb-comments — confluence_get_comments с page_id <id>.
# Первая строка вывода — итог: NO_ARG, BAD_KIND, NO_JOURNAL, NOT_FOUND (такого вызова с ответом
# в журнале нет), IN_FILE (ответ ушёл в файл — его путь следом, отдай render.sh его), иначе —
# вывод render.sh. Журнал не меняет. Нужен jq.
set -u
. "$(dirname "$0")/lib.sh"

if [ $# -lt 4 ] || [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ] || [ -z "$4" ]; then
  say "NO_ARG"
  exit 2
fi
case $2 in
  jira) tool=jira_get_issue arg=issue_key ;;
  kb | kb-raw) tool=confluence_get_page arg=page_id ;;
  kb-comments) tool=confluence_get_comments arg=page_id ;;
  *)
    say "BAD_KIND $2"
    exit 2
    ;;
esac
if ! command -v jq >/dev/null 2>&1; then
  say "NO_JQ"
  exit 5
fi

case $1 in
  */*) journal=$1 ;;
  *)
    journal=
    for f in "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/projects/*/"$1".jsonl; do
      [ -f "$f" ] && journal=$f && break
    done
    ;;
esac
if [ -z "$journal" ] || [ ! -f "$journal" ]; then
  say "NO_JOURNAL $1"
  exit 3
fi

work=$(mktemp -d "${TMPDIR:-/tmp}/sae-session.XXXXXX") || exit 6
trap 'rm -rf "$work"' EXIT

# Вызовы — tool_use в репликах ассистента, ответы — tool_result с тем же id в репликах
# человека. Недописанная строка журнала (запись ещё идёт) не кончается на «}» — её отсекает
# grep: jq -R для этого не годится, он рвёт многобайтные символы на длинных строках.
grep -a '}$' "$journal" >"$work/journal"
if ! jq -rn --arg tool "$tool" --arg arg "$arg" --arg id "$3" --arg kind "$2" '
  def wanted: (.name | endswith("__" + $tool))
    and ((.input[$arg] // "" | tostring) == $id)
    and (if $kind == "kb-raw" then .input.convert_to_markdown == false
         elif $kind == "kb" then .input.convert_to_markdown != false
         else true end);
  reduce (inputs | (.message.content? // empty) | if type == "array" then .[] else empty end) as $p
    ({calls: {}, last: null};
     if $p.type == "tool_use" and ($p | wanted) then .calls[$p.id] = true
     elif $p.type == "tool_result" and (.calls[$p.tool_use_id // ""] // false)
       and ($p.is_error // false) == false then .last = $p.content
     else . end)
  | .last
  | if . == null then empty
    elif type == "string" then .
    else (map(select(.type == "text") | .text) | join("")) end
' "$work/journal" >"$work/text" 2>"$work/err"; then
  say "JOURNAL_FAILED $journal"
  cat "$work/err"
  exit 6
fi
if [ ! -s "$work/text" ]; then
  say "NOT_FOUND $2 $3"
  exit 4
fi
# Большой ответ Claude Code кладёт в файл, в журнале — только путь к нему.
if ! jq -e . "$work/text" >/dev/null 2>&1; then
  saved=$(grep -oE '/[^ ]*/tool-results/[^ ]+' "$work/text" | head -n 1 | sed -E 's/[.,;:]+$//')
  if [ -n "$saved" ]; then
    say "IN_FILE $saved"
    exit 4
  fi
  say "NOT_JSON $2 $3"
  exit 4
fi
sh "$(dirname "$0")/render.sh" "$2" "$work/text" "$4"

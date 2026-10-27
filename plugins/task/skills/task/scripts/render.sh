#!/bin/sh
# render.sh <вид> <ответ MCP> <папка> — пишет md из ответа MCP, который Claude Code сохранил
# в файл (большие ответы в разговор не попадают). Вид:
#   jira    — jira_get_issue → <папка>/карточка.md: поля, описание, подзадачи, связи, вложения,
#             комментарии, удалённые ссылки; поля, которых шаблон не знает, — JSON в конце;
#   kb      — confluence_get_page (markdown) → <папка>/статья.md: шапка, текст, вложения;
#   kb-raw  — confluence_get_page (convert_to_markdown=false) → <папка>/исходник.html;
#   kb-comments — confluence_get_comments → <папка>/комментарии.md; дата у комментариев КБ
#             приходит пустой — «дата не указана».
# Тексты переносятся как есть, ничего не сокращается. Папка — внутри «…/материалы/»,
# создаётся. Файл уже есть — перезаписывается (это выгрузка, не правка владельца).
# Первая строка вывода — итог: WROTE <файл>, EMPTY (комментариев нет, файл не пишется),
# BAD_KIND, NO_FILE, NOT_JSON, NOT_MATERIALS, NO_ARG или код сбоя. Нужен jq.
set -u
. "$(dirname "$0")/lib.sh"

if [ $# -lt 3 ] || [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ]; then
  say "NO_ARG"
  exit 2
fi
kind=$1
case $kind in
  jira) name=карточка.md ;;
  kb) name=статья.md ;;
  kb-raw) name=исходник.html ;;
  kb-comments) name=комментарии.md ;;
  *)
    say "BAD_KIND $kind"
    exit 2
    ;;
esac
if [ ! -f "$2" ]; then
  say "NO_FILE $2"
  exit 3
fi
abs_path "$3"
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
# Ответ — {"result": "<JSON строкой>"}, массив частей [{type, text}] или сам объект.
# Комментарии — массив, остальное — объект.
body_def='
  def body: if type == "object" and (.result | type) == "string" then (.result | fromjson)
            elif type == "array" and (.[0].type? == "text") then (map(select(.type == "text") | .text | fromjson) | first)
            else . end;
'
want=object
[ "$kind" = kb-comments ] && want=array
if ! jq -e --arg want "$want" "$body_def"' body | type == $want' "$2" >/dev/null 2>&1; then
  say "NOT_JSON $2"
  exit 4
fi
if [ "$kind" = kb-comments ] && jq -e "$body_def"' body | length == 0' "$2" >/dev/null 2>&1; then
  say "EMPTY"
  exit 0
fi
if ! err=$(mkdir -p "$dest" 2>&1); then
  say "MKDIR_FAILED $dest"
  say "$err"
  exit 6
fi

prelude=$body_def'
  def txt: if . == null then "" elif type == "string" then gsub("\r"; "")
           elif type == "object" then (.display_name // .name // .value // .key // tojson)
           elif type == "array" then (map(txt) | join(", "))
           else tostring end;
  def row($k; $v): if ($v | txt) == "" then empty else "| \($k) | \($v | txt | gsub("\n"; " ") | gsub("\\|"; "\\|")) |" end;
'

case $kind in
  jira)
    program=$prelude'
      body as $i
      | [
          "# \($i.key): \($i.summary | txt)",
          "",
          "| Поле | Значение |",
          "| --- | --- |",
          row("Ссылка"; $i.browse_url),
          row("Тип"; $i.issue_type // $i.issuetype),
          row("Статус"; $i.status),
          row("Приоритет"; $i.priority),
          row("Исполнитель"; $i.assignee),
          row("Автор"; $i.reporter),
          row("Компоненты"; $i.components),
          row("Метки"; $i.labels),
          row("Версии"; $i.fix_versions // $i.fixVersions),
          row("Родитель"; ($i.parent | if type == "object" then "\(.key) \(.summary // .fields.summary // "")" else . end)),
          row("Эпик"; ($i.epic_key // $i.epic_link // ($i.epic | if type == "object" then .key else . end))),
          row("Создана"; $i.created),
          row("Обновлена"; $i.updated),
          "",
          "## Описание",
          "",
          (($i.description | txt) | if . == "" then "нет" else . end),
          "",
          "## Подзадачи",
          "",
          (($i.subtasks // []) | if length == 0 then "нет" else
            (map("- \(.key) — \(.summary // .fields.summary // "" | txt) (\(.status // .fields.status | txt))") | join("\n")) end),
          "",
          "## Связи",
          "",
          (($i.issuelinks // $i.issue_links // []) | if length == 0 then "нет" else
            (map(
              if .outward_issue or .outwardIssue then
                "- \(.type.outward // .type.name // "связь" | txt): \((.outward_issue // .outwardIssue) | "\(.key) \(.summary // .fields.summary // "" | txt)")"
              elif .inward_issue or .inwardIssue then
                "- \(.type.inward // .type.name // "связь" | txt): \((.inward_issue // .inwardIssue) | "\(.key) \(.summary // .fields.summary // "" | txt)")"
              else "- \(tojson)" end
            ) | join("\n")) end),
          "",
          "## Вложения",
          "",
          (($i.attachments // $i.attachment // []) | if length == 0 then "нет" else
            (map("- \(.filename) — \(.size) байт, \(.content_type // .mimeType // "?") — \(.url // .content // "")") | join("\n")) end),
          "",
          "## Удалённые ссылки",
          "",
          (($i.remote_links // []) | if length == 0 then "нет" else
            (map("- \(.title // .object.title // "" | txt) — \(.url // .object.url // "")") | join("\n")) end),
          "",
          "## Комментарии",
          "",
          (($i.comments // []) | if length == 0 then "нет" else
            (map("### \(.author | txt) — \(.created // "" | txt)\n\n\(.body // "" | txt)") | join("\n\n")) end),
          "",
          "## Прочие поля",
          "",
          ($i | del(.id, .key, .summary, .browse_url, .issue_type, .issuetype, .status, .priority,
                   .assignee, .reporter, .components, .labels, .fix_versions, .fixVersions, .parent,
                   .epic_key, .epic_link, .epic, .created, .updated, .description, .subtasks,
                   .issuelinks, .issue_links, .attachments, .attachment, .remote_links, .comments)
            | if length == 0 then "нет" else "```json\n\(.)\n```" end)
        ]
      | join("\n")
    '
    ;;
  kb)
    program=$prelude'
      body as $b
      | ($b.metadata // $b) as $m
      | [
          "# \($m.title | txt)",
          "",
          "| Поле | Значение |",
          "| --- | --- |",
          row("id"; $m.id),
          row("Пространство"; ($m.space | if type == "object" then "\(.key) — \(.name)" else . end)),
          row("Ссылка"; $m.url),
          row("Автор"; $m.author),
          row("Версия"; $m.version),
          row("Создана"; $m.created),
          row("Обновлена"; $m.updated),
          "",
          "---",
          "",
          ($m.content.value // $b.content.value // $b.content // "" | txt),
          "",
          "---",
          "",
          "## Вложения",
          "",
          (($m.attachments // []) | if length == 0 then "нет" else
            (map("- \(.title) — \(.file_size // .extensions.fileSize // "?") байт, \(.media_type // .extensions.mediaType // "?"), id \(.id)") | join("\n")) end)
        ]
      | join("\n")
    '
    ;;
  kb-raw)
    program=$prelude'
      body | (.content.value // .metadata.content.value // .content // "") | txt
    '
    ;;
  kb-comments)
    program=$prelude'
      body as $c
      | [
          "# Комментарии: \($c[0].title // "" | txt | sub("^Re: "; ""))",
          "",
          ($c | map(
            "### \(.author | txt) — \(.created // "" | txt | if . == "" then "дата не указана" else . end)"
            + " (\(.location // "?" | txt), id \(.id))\n\n\(.body // "" | txt)"
          ) | join("\n\n"))
        ]
      | join("\n")
    '
    ;;
esac

if ! err=$(jq -r "$program" "$2" 2>&1 >"$dest/$name.tmp"); then
  rm -f "$dest/$name.tmp"
  say "RENDER_FAILED $dest/$name"
  say "$err"
  exit 6
fi
mv "$dest/$name.tmp" "$dest/$name"
say "WROTE $dest/$name"
